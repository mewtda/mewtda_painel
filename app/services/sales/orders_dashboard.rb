module Sales
  # Dashboard da tela de Pedidos: os números que o lojista mais olha num período (faturamento, pedidos, ticket,
  # itens por pedido, descontos, cancelamentos), comparados com o período anterior de mesmo tamanho, e de onde
  # vêm as vendas (dia, hora, dia da semana, clientes novos x recorrentes, estados, cupons, frete).
  # Faturamento = total pago dos pedidos não cancelados (com frete), o mesmo da aba Pedidos.
  class OrdersDashboard
    PRESETS = SiteSummary::PRESETS
    WEEKDAYS = %w[Dom Seg Ter Qua Qui Sex Sáb].freeze
    PAID_SQL = 'COALESCE(orders.total_price, ' \
               'COALESCE(orders.subtotal_price, 0) + COALESCE(orders.total_shipping_price, 0))'.freeze
    DAY_SQL = LocalDate.sql('orders.shopify_creation_date')
    STATE_JOIN = 'INNER JOIN customer_profiles cp ON cp.client_id = orders.client_id ' \
                 'AND cp.customer_id = orders.customer_id'.freeze
    LOCAL_TIME_SQL = "(orders.shopify_creation_date AT TIME ZONE 'UTC' AT TIME ZONE '#{LocalDate::TIME_ZONE}')".freeze
    TOP = 10

    attr_reader :client, :from, :to, :preset

    def initialize(client:, preset: nil, from: nil, to: nil)
      @client = client
      @from, @to, @preset = SiteSummary.period_for(preset, from:, to:)
    end

    def days = (to - from).to_i + 1
    def previous_range = (from - days)..(from - 1)

    def kpis
      @kpis ||= begin
        current = totals(from..to)
        previous = totals(previous_range)
        current.to_h { |key, value| [key, { value:, change: change(value, previous[key]) }] }
      end
    end

    def daily
      @daily ||= begin
        rows = orders(from..to).group(Arel.sql(DAY_SQL))
                               .pluck(Arel.sql(DAY_SQL), Arel.sql("SUM(#{PAID_SQL})"), Arel.sql('COUNT(*)'))
                               .to_h { |date, revenue, count| [date.to_date, [revenue.to_f.round(2), count]] }
        (from..to).map { |day| { date: day, revenue: rows.dig(day, 0) || 0.0, orders: rows.dig(day, 1) || 0 } }
      end
    end

    def by_hour
      counts = orders(from..to).group(Arel.sql("EXTRACT(HOUR FROM #{LOCAL_TIME_SQL})::int")).count
      (0..23).map { |hour| counts[hour] || 0 }
    end

    def by_weekday
      counts = orders(from..to).group(Arel.sql("EXTRACT(DOW FROM #{LOCAL_TIME_SQL})::int")).count
      (0..6).map { |day| counts[day] || 0 }
    end

    # Pedido de cliente novo = o primeiro pedido (não cancelado) dele na loja.
    def customers
      @customers ||= begin
        scope = orders(from..to)
        returning_sql = 'EXISTS (SELECT 1 FROM orders earlier WHERE earlier.client_id = orders.client_id ' \
                        'AND earlier.customer_id = orders.customer_id AND earlier.cancelled_at IS NULL ' \
                        'AND earlier.shopify_creation_date < orders.shopify_creation_date)'
        rows = scope.where.not(customer_id: nil)
                    .group(Arel.sql(returning_sql))
                    .pluck(Arel.sql(returning_sql), Arel.sql('COUNT(*)'), Arel.sql("SUM(#{PAID_SQL})"),
                           Arel.sql('COUNT(DISTINCT orders.customer_id)'))
                    .to_h do |returning, count, revenue, people|
                      [returning ? :returning : :new, { orders: count, revenue: revenue.to_f, people: }]
                    end
        empty = { orders: 0, revenue: 0.0, people: 0 }
        { new: rows[:new] || empty, returning: rows[:returning] || empty,
          guest: scope.where(customer_id: nil).count }
      end
    end

    def shipping
      @shipping ||= begin
        scope = orders(from..to)
        total = scope.count
        free = scope.where('COALESCE(orders.total_shipping_price, 0) = 0').count
        paid = scope.where('orders.total_shipping_price > 0')
        { free_share: total.positive? ? free * 100.0 / total : 0, free:,
          average: paid.average(:total_shipping_price).to_f, total: scope.sum(:total_shipping_price).to_f }
      end
    end

    def states
      orders(from..to).joins(STATE_JOIN)
                      .where.not(cp: { state: [nil, ''] })
                      .group(Arel.sql('UPPER(cp.state)'))
                      .order(Arel.sql("SUM(#{PAID_SQL}) DESC"))
                      .limit(TOP)
                      .pluck(Arel.sql('UPPER(cp.state)'), Arel.sql('COUNT(*)'), Arel.sql("SUM(#{PAID_SQL})"))
                      .map { |state, count, revenue| { state:, orders: count, revenue: revenue.to_f } }
    end

    def coupons
      orders(from..to).where.not(discount_code: [nil, ''])
                      .group(Arel.sql('UPPER(orders.discount_code)'))
                      .order(Arel.sql('COUNT(*) DESC'))
                      .limit(TOP)
                      .pluck(Arel.sql('UPPER(orders.discount_code)'), Arel.sql('COUNT(*)'),
                             Arel.sql("SUM(#{PAID_SQL})"), Arel.sql('SUM(COALESCE(orders.total_discounts, 0))'))
                      .map do |code, count, revenue, discount|
                        { code:, orders: count, revenue: revenue.to_f, discount: discount.to_f }
                      end
    end

    def biggest_orders
      orders(from..to).includes(:customer).order(Arel.sql("#{PAID_SQL} DESC")).limit(TOP)
    end

    private

    def totals(range)
      scope = orders(range)
      count = scope.count
      revenue = scope.sum(Arel.sql(PAID_SQL)).to_f.round(2)
      units = OrderItem.where(order_id: scope.select(:id)).where(canceled: [false, nil]).sum(:quantity).to_i
      cancelled = all_orders(range).where.not(cancelled_at: nil)
      { revenue:, orders: count,
        average_ticket: count.positive? ? (revenue / count).round(2) : nil,
        items_per_order: count.positive? ? (units.to_f / count).round(2) : nil,
        discounts: scope.sum('COALESCE(orders.total_discounts, 0)').to_f.round(2),
        cancelled: cancelled.count }
    end

    def all_orders(range) = Order.where(client_id: client.id, shopify_creation_date: time_range(range))
    def orders(range) = all_orders(range).not_cancelled

    def time_range(range)
      zone = ActiveSupport::TimeZone[LocalDate::TIME_ZONE]
      zone.local(range.first.year, range.first.month, range.first.day)..
        zone.local(range.last.year, range.last.month, range.last.day).end_of_day
    end

    def change(current, previous)
      return nil if current.nil? || previous.nil? || previous.to_f.zero?

      ((current.to_f - previous.to_f) / previous.to_f * 100).round(1)
    end
  end
end
