module Sales
  # Resumo do site (tela inicial do CRM): vendas da Shopify x investimento em
  # anúncios num período, comparado com o período anterior de mesmo tamanho.
  # Mesmas bases do Dashboard metas: com o relatório da Shopify, faturamento =
  # vendas totais (bruto − descontos − devoluções + frete + impostos), igual ao
  # admin da loja; sem ele, subtotal (já com descontos) + frete dos pedidos não
  # cancelados. Investimento = custos de anúncio cadastrados/sincronizados,
  # distribuídos igualmente pelos dias que cobrem.
  class SiteSummary
    PRESETS = {
      'hoje' => 'Hoje', 'ontem' => 'Ontem', '7' => '7 dias', '14' => '14 dias', '30' => '30 dias',
      'mes' => 'Este mês', 'mes_passado' => 'Mês passado', '90' => '90 dias'
    }.freeze
    DEFAULT_PRESET = '7'.freeze
    TOP_PRODUCTS = 15

    attr_reader :client, :from, :to, :preset

    def self.period_for(preset, from: nil, to: nil, today: Time.zone.today)
      custom = parse_date(from) && parse_date(to)
      return [parse_date(from), [parse_date(to), today].min, nil] if custom && parse_date(from) <= parse_date(to)

      preset = DEFAULT_PRESET unless PRESETS.key?(preset)
      range = case preset
              when 'hoje' then [today, today]
              when 'ontem' then [today - 1, today - 1]
              when 'mes' then [today.beginning_of_month, today]
              when 'mes_passado' then [today.prev_month.beginning_of_month, today.prev_month.end_of_month]
              else [today - (preset.to_i - 1), today]
              end
      [*range, preset]
    end

    def self.parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def initialize(client:, preset: nil, from: nil, to: nil, report: nil)
      @client = client
      @from, @to, @preset = self.class.period_for(preset, from: from, to: to)
      @report = report || ShopifyReport.new(client: client)
    end

    # true quando os números vieram do relatório da Shopify.
    def shopify_report?
      !report_totals(from..to).nil?
    end

    # Caminho do faturamento como no admin da Shopify, ou nil sem o relatório.
    def revenue_breakdown
      row = report_totals(from..to)
      return unless row

      { gross: money(row['gross_sales']), discounts: money(row['discounts']).abs,
        returns: money(row['returns']).abs, shipping: money(row['shipping_charges']),
        taxes: money(row['taxes']), total: money(row['total_sales']) }
    end

    def days
      (from..to).to_a
    end

    def previous_range
      length = days.size
      (from - length)..(from - 1)
    end

    def kpis
      @kpis ||= begin
        current = totals(from..to)
        previous = totals(previous_range)
        %i[revenue orders average_ticket ad_cost roas cpa].index_with do |key|
          { value: current[key], change: change(current[key], previous[key]) }
        end
      end
    end

    def daily
      @daily ||= begin
        orders = report_daily(from..to) || order_totals_by_day(from..to)
        ads = ad_cost_by_day(from..to)
        days.map do |day|
          entry = orders[day] || { revenue: 0.0, orders: 0 }
          { date: day, revenue: entry[:revenue].round(2), orders: entry[:orders], ad_cost: ads[day].to_f.round(2) }
        end
      end
    end

    # Investimento por plataforma no período (Meta, Google...).
    def ad_cost_by_platform
      totals = Hash.new(0.0)
      each_ad_cost_day(from..to) { |cost, _day, per_day| totals[cost.platform_label] += per_day }
      totals.transform_values { |v| v.round(2) }.sort_by { |_, v| -v }.to_h
    end

    def cancelled_orders
      Order.where(client_id: client.id, shopify_creation_date: time_range(from..to)).where.not(cancelled_at: nil).count
    end

    def top_products
      @top_products ||= OrderItem.joins(:order)
                                 .merge(orders_scope(from..to))
                                 .where(canceled: [false, nil])
                                 .left_joins(:product)
                                 .group(Arel.sql("COALESCE(products.shopify_product_name, order_items.sku, 'Sem nome')"))
                                 .order(Arel.sql('SUM(order_items.price * order_items.quantity) DESC'))
                                 .limit(TOP_PRODUCTS)
                                 .pluck(Arel.sql("COALESCE(products.shopify_product_name, order_items.sku, 'Sem nome')"),
                                        Arel.sql('SUM(order_items.quantity)'),
                                        Arel.sql('COUNT(DISTINCT order_items.order_id)'),
                                        Arel.sql('SUM(order_items.price * order_items.quantity)'))
                                 .map do |name, units, orders, revenue|
          { name: name, units: units.to_i, orders: orders.to_i, revenue: revenue.to_f.round(2) }
        end
    end

    private

    def totals(range)
      if (row = report_totals(range))
        revenue = money(row['total_sales']).round(2)
        orders = row['orders'].to_i
      else
        scope = orders_scope(range)
        revenue = scope.sum(Arel.sql('COALESCE(subtotal_price, 0) + COALESCE(total_shipping_price, 0)')).to_f.round(2)
        orders = scope.count
      end
      ad_cost = ad_cost_by_day(range).values.sum.round(2)

      { revenue: revenue, orders: orders,
        average_ticket: orders.positive? ? (revenue / orders).round(2) : nil,
        ad_cost: ad_cost,
        roas: ad_cost.positive? ? (revenue / ad_cost).round(2) : nil,
        cpa: ad_cost.positive? && orders.positive? ? (ad_cost / orders).round(2) : nil }
    end

    def report_totals(range)
      @report_totals ||= {}
      return @report_totals[range] if @report_totals.key?(range)

      @report_totals[range] = @report.rows(
        'FROM sales SHOW total_sales, gross_sales, discounts, returns, shipping_charges, taxes, orders ' \
        "WITH #{ShopifyReport::WITH_OPTIONS} #{ShopifyReport.range(range.first, range.last)}"
      )&.first
    end

    def report_daily(range)
      rows = @report.rows(
        "FROM sales SHOW total_sales, orders GROUP BY day WITH #{ShopifyReport::WITH_OPTIONS} " \
        "#{ShopifyReport.range(range.first, range.last)} ORDER BY day ASC"
      )
      return if rows.nil?

      rows.to_h { |row| [Date.iso8601(row['day'].to_s[0, 10]), { revenue: money(row['total_sales']), orders: row['orders'].to_i }] }
    rescue ArgumentError
      nil
    end

    def money(value)
      BigDecimal(value.to_s.presence || '0').to_f
    end

    def orders_scope(range)
      Order.not_cancelled.where(client_id: client.id, shopify_creation_date: time_range(range))
    end

    # As datas de pedido estão em UTC e o cliente opera no horário de Brasília.
    def time_range(range)
      zone = ActiveSupport::TimeZone[LocalDate::TIME_ZONE]
      zone.local(range.first.year, range.first.month, range.first.day)..
        zone.local(range.last.year, range.last.month, range.last.day).end_of_day
    end

    def order_totals_by_day(range)
      local_date = LocalDate.sql('shopify_creation_date')
      orders_scope(range).group(Arel.sql(local_date))
                         .pluck(Arel.sql(local_date),
                                Arel.sql('SUM(COALESCE(subtotal_price, 0) + COALESCE(total_shipping_price, 0))'),
                                Arel.sql('COUNT(*)'))
                         .to_h { |date, revenue, count| [date.to_date, { revenue: revenue.to_f, orders: count }] }
    end

    def ad_cost_by_day(range)
      totals = Hash.new(0.0)
      each_ad_cost_day(range) { |_cost, day, per_day| totals[day] += per_day }
      totals
    end

    def each_ad_cost_day(range)
      client.ad_costs.overlapping(range.first, range.last).find_each do |cost|
        cost_days = (cost.start_date..cost.end_date).to_a
        next if cost_days.empty?

        per_day = cost.amount.to_f / cost_days.size
        cost_days.each { |day| yield cost, day, per_day if range.cover?(day) }
      end
    end

    def change(current, previous)
      return nil if current.nil? || previous.nil? || previous.to_f.zero?

      ((current.to_f - previous.to_f) / previous.to_f * 100).round(1)
    end
  end
end
