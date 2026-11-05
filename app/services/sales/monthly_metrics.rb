module Sales
  class MonthlyMetrics
    def initialize(client:, year:, month:, tag: nil)
      @client = client
      @year = year
      @month = month
      @tag = tag
    end

    def call
      {
        # :shopify = números do relatório da Shopify; :approximate = pedidos sincronizados.
        metrics_source: report_sales ? :shopify : :approximate,
        revenue: revenue,
        gross_sales: gross_sales,
        returns: returns,
        taxes: taxes,
        discounts: discounts,
        net_of_discounts: net_of_discounts,
        shipping: shipping,
        orders_count: orders_count,
        avg_ticket: avg_ticket,
        ad_cost: ad_cost,
        ad_cost_available: ad_cost_available?,
        ad_cost_by_platform: ad_cost_by_platform,
        configured_platforms: configured_platforms,
        roas: roas,
        new_customers_count: new_customers_count,
        cac: cac,
        conversion_rate: conversion_rate,
        # Meta de "Faturamento" = mesmo valor do card principal (Bruto − Descontos + Frete).
        revenue_target: goal&.revenue_target,
        revenue_target_progress_pct: progress_pct(revenue, goal&.revenue_target),
        revenue_target_remaining: remaining(revenue, goal&.revenue_target),
        roas_target: goal&.roas_target,
        roas_target_progress_pct: progress_pct(roas, goal&.roas_target),
        roas_target_remaining: remaining(roas, goal&.roas_target),
        avg_ticket_target: goal&.avg_ticket_target,
        avg_ticket_target_progress_pct: progress_pct(avg_ticket, goal&.avg_ticket_target),
        avg_ticket_target_remaining: remaining(avg_ticket, goal&.avg_ticket_target),
        conversion_rate_target: goal&.conversion_rate_target,
        conversion_rate_target_progress_pct: progress_pct(conversion_rate, goal&.conversion_rate_target),
        conversion_rate_target_remaining: remaining(conversion_rate, goal&.conversion_rate_target),
        cac_target: goal&.cac_target,
        cac_target_status: ceiling_status(cac, goal&.cac_target),
        cac_target_diff: ceiling_diff(cac, goal&.cac_target),
        tagged_revenue_tag: goal&.tagged_revenue_tag,
        tagged_revenue: tagged_revenue,
        tagged_revenue_source: tagged_revenue_source,
        tagged_revenue_target: goal&.tagged_revenue_target,
        tagged_revenue_target_progress_pct: progress_pct(tagged_revenue, goal&.tagged_revenue_target),
        tagged_revenue_target_remaining: remaining(tagged_revenue, goal&.tagged_revenue_target)
      }
    end

    private

    attr_reader :client, :year, :month, :tag

    def period
      start = Time.zone.local(year, month, 1).beginning_of_day
      start..start.end_of_month
    end

    # Pedidos NÃO cancelados: base de tudo (faturamento, contagem, ticket médio).
    # Reembolsos/cancelamentos não entram mais na conta — só simplesmente ignora
    # o pedido cancelado, sem tentar reconciliar com o relatório do Shopify.
    def orders_scope
      scope = Order.not_cancelled.where(client_id: client.id, shopify_creation_date: period)
      scope = scope.with_any_tag(tag) if tag.present?
      scope
    end

    # Com o relatório da Shopify: vendas totais (bruto − descontos − devoluções
    # + frete + impostos), igual ao admin da loja. Sem ele: Bruto − Descontos + Frete
    # dos pedidos sincronizados.
    def revenue
      return money(report_sales['total_sales']) if report_sales

      net_of_discounts + shipping
    end

    def returns
      money(report_sales['returns']).abs if report_sales
    end

    def taxes
      money(report_sales['taxes']) if report_sales
    end

    # subtotal_price do Shopify já vem líquido de descontos (não é o "bruto" de fato).
    # Reconstituímos o valor bruto somando o desconto de volta, pra a UI mostrar
    # o caminho completo: Bruto - Descontos = Faturamento.
    def gross_sales
      return money(report_sales['gross_sales']) if report_sales

      net_of_discounts + discounts
    end

    def net_of_discounts
      return gross_sales - discounts if report_sales

      orders_scope.sum(:subtotal_price)
    end

    def discounts
      return money(report_sales['discounts']).abs if report_sales

      orders_scope.sum(:total_discounts)
    end

    def shipping
      return money(report_sales['shipping_charges']) if report_sales

      orders_scope.sum(:total_shipping_price)
    end

    def orders_count
      return report_sales['orders'].to_i if report_sales

      orders_scope.count
    end

    # Baseado no valor original de cada pedido (não no Faturamento ajustado por
    # reembolsos de outros períodos), pra representar o ticket de fato daquele pedido.
    def avg_ticket
      return money(report_sales['average_order_value']).round(2) if report_sales && orders_count.positive?
      return nil if orders_count.zero?

      orders_scope.sum(:total_price) / orders_count
    end

    def configured_platforms
      client.ad_costs.distinct.pluck(:platform)
    end

    def ad_costs_in_period
      client.ad_costs.overlapping(period.first.to_date, period.last.to_date)
    end

    def ad_cost_available?
      ad_costs_in_period.exists?
    end

    def ad_cost
      ad_costs_in_period.sum(:amount)
    end

    def ad_cost_by_platform
      ad_costs_in_period.group(:platform).sum(:amount)
    end

    def roas
      return nil unless ad_cost_available?
      return nil if ad_cost.zero?

      (revenue / ad_cost).round(2)
    end

    def new_customers_count
      return report_sales['new_customers'].to_i if report_sales

      Customer
        .joins(:orders)
        .where(orders: { client_id: client.id, cancelled_at: nil })
        .group('customers.id')
        .having('MIN(orders.shopify_creation_date) BETWEEN ? AND ?', period.first, period.last)
        .count
        .length
    end

    def cac
      return nil unless ad_cost_available?
      return nil if new_customers_count.zero?

      (ad_cost / new_customers_count).round(2)
    end

    def unique_sessions
      ShopifyEvent
        .where(client_id: client.id, kind: 'page_viewed', created_at: period)
        .distinct
        .count(:session_id)
    end

    # Pedidos reais do período inteiro (sem filtro de tag) / sessões totais.
    # Usa o pedido de fato — sincronizado da API da Shopify — em vez do evento
    # de pixel "checkout_completed", que é disparado por JS no navegador do
    # cliente e sabidamente perde conversões (ad blocker, timing do redirect).
    def period_orders_count
      Order.not_cancelled.where(client_id: client.id, shopify_creation_date: period).count
    end

    def conversion_rate
      return (report_sessions['conversion_rate'].to_f * 100).round(2) if report_sessions
      return nil if unique_sessions.zero?

      (period_orders_count.to_f / unique_sessions * 100).round(2)
    end

    # Faturamento (Bruto − Descontos) só dos pedidos com a tag configurada na meta
    # (ex.: nome de uma vendedora).
    # Meta por tag: o número vem do relatório da Shopify (igual ao que a loja
    # mostra). Se a Shopify não responder, cai na soma dos pedidos sincronizados
    # e a tela avisa que é aproximado.
    def tagged_revenue
      return @tagged_revenue if defined?(@tagged_revenue)

      goal_tag = goal&.tagged_revenue_tag
      return @tagged_revenue = nil if goal_tag.blank?

      shopify = Sales::ShopifyTaggedSales.new(client: client, from: period.first, to: period.last, tags: goal_tag).total
      @tagged_revenue_source = shopify ? :shopify : :approximate
      @tagged_revenue = shopify || orders_scope.with_any_tag(goal_tag).sum(:subtotal_price)
    end

    def tagged_revenue_source
      tagged_revenue
      @tagged_revenue_source
    end

    def shopify_report
      @shopify_report ||= Sales::ShopifyReport.new(client: client)
    end

    # Resumo do mês no relatório de vendas da Shopify (respeita o filtro de tag).
    def report_sales
      return @report_sales if defined?(@report_sales)

      where = ''
      if tag.present?
        tags = Sales::ShopifyReport.tags(tag)
        return @report_sales = nil if tags.empty?

        where = "WHERE #{Sales::ShopifyReport.tag_condition(tags)} "
      end
      query = 'FROM sales SHOW total_sales, gross_sales, discounts, returns, net_sales, shipping_charges, taxes, ' \
              "orders, average_order_value, new_customers #{where}WITH #{Sales::ShopifyReport::WITH_OPTIONS} " \
              "#{Sales::ShopifyReport.range(period.first, period.last)}"
      @report_sales = shopify_report.rows(query)&.first
    end

    # Sessões e conversão da loja inteira no mês (relatório de sessões da Shopify).
    def report_sessions
      return @report_sessions if defined?(@report_sessions)

      query = "FROM sessions SHOW sessions, conversion_rate WITH #{Sales::ShopifyReport::WITH_OPTIONS} " \
              "#{Sales::ShopifyReport.range(period.first, period.last)}"
      @report_sessions = shopify_report.rows(query)&.first
    end

    def money(value)
      BigDecimal(value.to_s.presence || '0')
    end

    def goal
      return @goal if defined?(@goal)

      @goal = client.goals.find_by(year: year, month: month)
    end

    def progress_pct(actual, target)
      return nil if target.blank? || target.to_f.zero? || actual.nil?

      ((actual.to_f / target.to_f) * 100).round(1)
    end

    def remaining(actual, target)
      return nil if target.blank? || actual.nil?

      [target.to_f - actual.to_f, 0].max.round(2)
    end

    # CAC é "quanto menor, melhor" — ao contrário das outras metas. :under quer
    # dizer que o custo de aquisição está dentro (ou abaixo) do teto definido.
    def ceiling_status(actual, target)
      return nil if target.blank? || actual.nil?

      actual.to_f <= target.to_f ? :under : :over
    end

    def ceiling_diff(actual, target)
      return nil if target.blank? || actual.nil?

      (target.to_f - actual.to_f).abs.round(2)
    end
  end
end
