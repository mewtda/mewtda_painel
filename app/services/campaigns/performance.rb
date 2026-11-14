module Campaigns
  class Performance
    ATTRIBUTION_DAYS = 7
    HOUR_BUCKET = 3
    HOUR_SQL = "EXTRACT(HOUR FROM occurred_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::int".freeze
    Result = Struct.new(:campaigns_count, :audience, :blocked, :failed, :sent, :investment, :revenue, :purchases,
                        :avg_ticket, :net, :tracked, :delivered, :bounced, :complaints, :opened, :clicked, :hours,
                        keyword_init: true) do
      def percent_of_audience(part) = rate(part, audience)
      def rate(part, whole) = whole.to_i.zero? ? 0 : part.to_f * 100 / whole
    end

    def initialize(campaigns)
      @campaigns = campaigns
    end

    def call
      count, audience, blocked, failed, sent = totals
      purchases, revenue = sales
      investment = sent * Billing::Invoice::EMAIL_PRICE_PER_THOUSAND / 1000
      Result.new(campaigns_count: count, audience:, blocked:, failed:, sent:, investment:, revenue:, purchases:,
                 avg_ticket: purchases.zero? ? 0 : revenue / purchases, net: revenue - investment, **engagement)
    end

    private

    attr_reader :campaigns

    def totals
      campaigns.pick(Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(recipients_count), 0)'),
                     Arel.sql('COALESCE(SUM(blocked_count), 0)'), Arel.sql('COALESCE(SUM(failed_count), 0)'),
                     Arel.sql('COALESCE(SUM(sent_count), 0)'))&.map(&:to_i) || Array.new(5, 0)
    end

    def engagement
      events = EmailEvent.where(campaign_id: campaigns.reorder(nil).select(:id))
      counts = events.group(:event_type).distinct.count(:campaign_recipient_id)
      { tracked: events.exists?, delivered: counts.fetch('delivery', 0), bounced: counts.fetch('bounce', 0),
        complaints: counts.fetch('complaint', 0), opened: counts.fetch('open', 0), clicked: counts.fetch('click', 0),
        hours: engagement_hours(events) }
    end

    def engagement_hours(events)
      per_hour = events.where(event_type: %w[open click]).group(Arel.sql(HOUR_SQL)).distinct.count(:campaign_recipient_id)
      buckets = (0...24).step(HOUR_BUCKET).index_with(0)
      per_hour.each { |hour, count| buckets[hour / HOUR_BUCKET * HOUR_BUCKET] += count }
      buckets
    end

    def sales
      count, revenue = Order.where(id: attributed_orders.select('orders.id'))
                            .pick(Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(total_price), 0)'))
      [count.to_i, revenue.to_d]
    end

    def attributed_orders
      Order.not_cancelled
           .joins('INNER JOIN customer_profiles cp ON cp.client_id = orders.client_id ' \
                  'AND (orders.customer_id = cp.customer_id OR orders.customer_id = ANY(cp.merged_customer_ids))')
           .joins("INNER JOIN campaign_recipients r ON r.customer_id = cp.customer_id AND r.status = 'sent'")
           .where('r.campaign_id IN (?)', campaigns.reorder(nil).select(:id))
           .where('orders.shopify_creation_date >= r.sent_at')
           .where("orders.shopify_creation_date < r.sent_at + INTERVAL '#{ATTRIBUTION_DAYS} days'")
    end
  end
end
