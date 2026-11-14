module BackInStock
  class Performance
    ATTRIBUTION_DAYS = 7
    TOP_LIMIT = 5
    NOTIFICATIONS_LIMIT = 12
    AGE_BUCKETS = [['Menos de 3 dias', 0...3], ['3 a 10 dias', 3...10], ['10 a 30 dias', 10...30],
                   ['1 a 3 meses', 30...90], ['Mais de 3 meses', 90..]].freeze
    DAY_SQL = "(%s AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date".freeze
    ATTRIBUTION_SQL = <<~SQL.squish.freeze
      FROM back_in_stock_alerts a
      JOIN customer_profiles cp ON cp.client_id = a.client_id AND LOWER(cp.email) = a.email
      JOIN orders o ON o.client_id = a.client_id AND o.cancelled_at IS NULL
        AND (o.customer_id = cp.customer_id OR o.customer_id = ANY(cp.merged_customer_ids))
      JOIN order_items oi ON oi.order_id = o.id
      JOIN products p ON p.id = oi.product_id AND p.shopify_variant_id = a.shopify_variant_id::text
      WHERE a.client_id = :client_id AND a.status = 'notified' AND a.notified_at IS NOT NULL
        AND o.shopify_creation_date >= a.notified_at
        AND o.shopify_creation_date < a.notified_at + INTERVAL '#{ATTRIBUTION_DAYS} days'
    SQL

    Totals = Struct.new(:variants, :requests, :notified, :purchases, :revenue, keyword_init: true)
    Result = Struct.new(:totals, :previous, :funnel, :requests_by_day, :notified_by_day, :revenue_by_day, :age_buckets,
                        :avg_age_days, :avg_notify_days, :conversion, :top_variants, :history, :notifications,
                        keyword_init: true) do
      def change(field)
        before = previous&.public_send(field).to_d
        return if previous.nil? || before.zero?

        ((totals.public_send(field).to_d - before) * 100 / before).to_f
      end
    end

    def initialize(client, period, sort: 'demand')
      @client = client
      @period = period
      @sort = BackInStockAlert::SORTS.key?(sort) ? sort : 'demand'
    end

    def call
      range = period.time_range
      Result.new(totals: totals(range), previous: (totals(previous_range) if previous_range), funnel: funnel(range),
                 requests_by_day: filled(requests_by_day(range)), notified_by_day: filled(notified_by_day(range)),
                 revenue_by_day: filled(revenue_by_day(range)), age_buckets: age_buckets, avg_age_days: avg_age_days,
                 avg_notify_days: avg_notify_days(range), conversion: conversion(range), **top(range),
                 notifications: notifications(range))
    end

    private

    attr_reader :client, :period, :sort

    def alerts = client.back_in_stock_alerts

    def previous_range
      return unless period.from

      @previous_range ||= begin
        span = (period.to - period.from).to_i + 1
        (period.from - span).in_time_zone.beginning_of_day..(period.from - 1).in_time_zone.end_of_day
      end
    end

    def totals(range)
      orders = attributed_orders(range)
      Totals.new(variants: alerts.where(created_at: range).distinct.count(:shopify_variant_id),
                 requests: alerts.where(created_at: range).count, notified: alerts.notified.where(notified_at: range).count,
                 purchases: orders.size, revenue: orders.sum { |order| order.total_price.to_d })
    end

    def funnel(range)
      created = alerts.where(created_at: range)
      ordered = ordered_alert_ids(created_at: range)
      notified = created.notified.count
      converted = created.notified.where(id: ordered).count
      { waiting: created.pending.count, notified: notified - converted, ordered: converted, cancelled: created.cancelled.count }
    end

    def requests_by_day(range) = alerts.where(created_at: range).group(Arel.sql(format(DAY_SQL, 'created_at'))).count

    def notified_by_day(range)
      alerts.notified.where(notified_at: range).group(Arel.sql(format(DAY_SQL, 'notified_at'))).count
    end

    def revenue_by_day(range)
      attributed_orders(range).group_by { |order| order[:ordered_at].in_time_zone.to_date }
                              .transform_values { |orders| orders.sum { |order| order.total_price.to_d } }
    end

    def filled(series)
      first = period.from || series.keys.min
      return {} unless first

      (first..period.to).index_with { |day| series.fetch(day, 0) }
    end

    def pending_ages
      @pending_ages ||= alerts.pending.pluck(:created_at).map { |created| (Time.current - created) / 1.day }
    end

    def age_buckets
      ages = pending_ages
      AGE_BUCKETS.map do |label, days|
        count = ages.count { |age| days.cover?(age) }
        { label:, count:, percent: ages.empty? ? 0 : count * 100.0 / ages.size }
      end
    end

    def avg_age_days = (pending_ages.sum / pending_ages.size if pending_ages.any?)

    def avg_notify_days(range)
      alerts.notified.where(notified_at: range).average(Arel.sql('EXTRACT(EPOCH FROM (notified_at - created_at)) / 86400'))&.to_f
    end

    def conversion(range)
      notified = alerts.notified.where(notified_at: range).count
      return if notified.zero?

      ordered_alert_ids(notified_at: range).size * 100.0 / notified
    end

    def top(_range)
      groups = alerts.pending.grouped_by_variant(sort).limit(TOP_LIMIT).to_a
      history = alerts.where(shopify_variant_id: groups.map(&:shopify_variant_id)).group(:shopify_variant_id).count
      { top_variants: groups, history: }
    end

    def notifications(range)
      recent = alerts.notified.where(notified_at: range).order(notified_at: :desc).limit(NOTIFICATIONS_LIMIT).to_a
      events = EmailEvent.where(back_in_stock_alert_id: recent.map(&:id)).group(:back_in_stock_alert_id)
                         .pluck(:back_in_stock_alert_id, Arel.sql('ARRAY_AGG(DISTINCT event_type)')).to_h
      recent.map { |alert| [alert, events.fetch(alert.id, [])] }
    end

    def attributed_orders(range)
      sql = "SELECT DISTINCT ON (o.id) o.id, o.total_price, o.shopify_creation_date AS ordered_at #{ATTRIBUTION_SQL} " \
            'AND o.shopify_creation_date BETWEEN :from AND :to ORDER BY o.id, a.notified_at'
      Order.find_by_sql([sql, binds(range)])
    end

    def ordered_alert_ids(created_at: nil, notified_at: nil)
      column, range = created_at ? ['a.created_at', created_at] : ['a.notified_at', notified_at]
      query = "SELECT DISTINCT a.id #{ATTRIBUTION_SQL} AND #{column} BETWEEN :from AND :to"
      ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql_array([query, binds(range)]))
    end

    def binds(range) = { client_id: client.id, from: range.begin || Time.zone.at(0), to: range.end }
  end
end
