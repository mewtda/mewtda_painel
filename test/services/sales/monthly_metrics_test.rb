require 'test_helper'

class Sales::MonthlyMetricsTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @integration_user = IntegrationUser.create!(
      name: 'Pixel', slug: "pixel-#{SecureRandom.hex(4)}", api_secret: SecureRandom.hex(8), client: @client
    )
  end

  def create_order(attrs = {})
    total = attrs[:total_price] || 100
    Order.create!({
      client: @client,
      shopify_order_id: SecureRandom.hex(6),
      shopify_creation_date: Time.zone.local(2026, 3, 15),
      subtotal_price: total,
      total_discounts: 0,
      total_price: total,
      total_shipping_price: 0,
      cancelled_at: nil,
      tags: nil
    }.merge(attrs))
  end

  def create_page_view(session_id, at: Time.zone.local(2026, 3, 15))
    ShopifyEvent.create!(
      client: @client, integration_user: @integration_user, kind: 'page_viewed',
      session_id: session_id, created_at: at
    )
  end

  def call(tag: nil)
    Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 3, tag: tag).call
  end

  test 'revenue is net of discounts plus shipping, gross_sales reconstructs the pre-discount value' do
    create_order(total_price: 100, subtotal_price: 120, total_discounts: 20)
    create_order(total_price: 50, subtotal_price: 50, total_discounts: 0)
    create_order(shopify_creation_date: Time.zone.local(2026, 2, 15), total_price: 999) # outside the month

    result = call

    assert_equal 190.0, result[:gross_sales].to_f
    assert_equal 20.0, result[:discounts].to_f
    assert_equal 170.0, result[:net_of_discounts].to_f
    assert_equal 170.0, result[:revenue].to_f
    assert_equal 2, result[:orders_count]
  end

  test 'excludes cancelled orders entirely from revenue and order count' do
    create_order(total_price: 100)
    create_order(total_price: 500, cancelled_at: Time.zone.local(2026, 3, 20))

    result = call

    assert_equal 100.0, result[:net_of_discounts].to_f
    assert_equal 100.0, result[:revenue].to_f
    assert_equal 1, result[:orders_count]
  end

  test 'avg_ticket is revenue divided by orders_count, nil when there are no orders' do
    create_order(total_price: 100)
    create_order(total_price: 300)

    assert_equal 200.0, call[:avg_ticket].to_f

    empty_client = Client.create!(name: 'Vazia', email: "vazia-#{SecureRandom.hex(4)}@example.com")
    result = Sales::MonthlyMetrics.new(client: empty_client, year: 2026, month: 3).call
    assert_nil result[:avg_ticket]
  end

  test 'tag filter restricts the order scope' do
    create_order(total_price: 100, tags: 'VendedoraElo, promo')
    create_order(total_price: 300, tags: 'outra-tag')
    create_page_view('s1')
    create_page_view('s2')

    result = call(tag: 'VendedoraElo')

    assert_equal 100.0, result[:revenue].to_f
    assert_equal 1, result[:orders_count]
  end

  test 'ad_cost_available is false when the client has ad costs but not for this period' do
    @client.ad_costs.create!(
      platform: 'meta', name: 'Campanha Fevereiro',
      start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 2, 28), amount: 100
    )
    create_order(total_price: 100)

    result = call

    assert_equal ['meta'], result[:configured_platforms]
    assert_not result[:ad_cost_available]
    assert_nil result[:roas]
    assert_nil result[:cac]
  end

  test 'roas is revenue / ad_cost and cac is ad_cost / new_customers_count when ad cost is registered for the period' do
    @client.ad_costs.create!(
      platform: 'meta', name: 'Campanha Março',
      start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31), amount: 100
    )

    new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(total_price: 400, customer: new_customer)

    result = call

    assert result[:ad_cost_available]
    assert_equal 100.0, result[:ad_cost].to_f
    assert_equal 4.0, result[:roas].to_f
    assert_equal 1, result[:new_customers_count]
    assert_equal 100.0, result[:cac].to_f
  end

  test 'ad_cost sums entries from every platform registered for the period' do
    @client.ad_costs.create!(
      platform: 'meta', name: 'Meta',
      start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31), amount: 100
    )
    @client.ad_costs.create!(
      platform: 'google_ads', name: 'Google',
      start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31), amount: 900
    )

    result = call

    assert_equal %w[google_ads meta], result[:configured_platforms].sort
    assert_equal 1000.0, result[:ad_cost].to_f
  end

  test 'new_customers_count only counts customers whose earliest non-cancelled order falls in the month' do
    returning_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(shopify_creation_date: Time.zone.local(2026, 1, 5), customer: returning_customer)
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 10), customer: returning_customer)

    brand_new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(shopify_creation_date: Time.zone.local(2026, 3, 12), customer: brand_new_customer)

    assert_equal 1, call[:new_customers_count]
  end

  test 'goal progress and remaining are computed against the revenue (incl. shipping) and roas targets' do
    @client.goals.create!(year: 2026, month: 3, revenue_target: 200, roas_target: 4)
    @client.ad_costs.create!(
      platform: 'meta', name: 'Meta',
      start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31), amount: 25
    )
    create_order(total_price: 150, subtotal_price: 150, total_shipping_price: 20)

    result = call

    assert_equal 170.0, result[:revenue].to_f # 150 (net) + 20 (frete)
    assert_equal 200.0, result[:revenue_target].to_f
    assert_equal 85.0, result[:revenue_target_progress_pct]
    assert_equal 30.0, result[:revenue_target_remaining].to_f
    assert_equal 4.0, result[:roas_target].to_f
    assert_equal 6.8, result[:roas].to_f
    assert_equal 170.0, result[:roas_target_progress_pct]
    assert_equal 0.0, result[:roas_target_remaining].to_f
  end

  test 'goal fields are nil when no goal is registered for the period' do
    create_order(total_price: 100)

    result = call

    assert_nil result[:revenue_target]
    assert_nil result[:revenue_target_progress_pct]
    assert_nil result[:roas_target]
  end

  test 'avg_ticket_target and conversion_rate_target progress are computed like the other goals' do
    @client.goals.create!(year: 2026, month: 3, avg_ticket_target: 100, conversion_rate_target: 50)
    create_order(total_price: 100)
    create_order(total_price: 300)
    create_page_view('s1')
    create_page_view('s2')

    result = call

    assert_equal 200.0, result[:avg_ticket].to_f
    assert_equal 200.0, result[:avg_ticket_target_progress_pct]
    assert_equal 0.0, result[:avg_ticket_target_remaining].to_f
    # conversion_rate usa pedidos reais (2) / acessos (2) = 100%, não o evento
    # de pixel "checkout_completed" — esse não entra mais na conta.
    assert_equal 100.0, result[:conversion_rate]
    assert_equal 200.0, result[:conversion_rate_target_progress_pct]
  end

  test 'cac_target is a ceiling: status is :under when actual CAC is at or below the target' do
    @client.goals.create!(year: 2026, month: 3, cac_target: 50)
    @client.ad_costs.create!(
      platform: 'meta', name: 'Meta',
      start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31), amount: 30
    )
    new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(total_price: 100, customer: new_customer)

    result = call

    assert_equal 30.0, result[:cac].to_f
    assert_equal :under, result[:cac_target_status]
    assert_equal 20.0, result[:cac_target_diff].to_f
  end

  test 'cac_target is a ceiling: status is :over when actual CAC exceeds the target' do
    @client.goals.create!(year: 2026, month: 3, cac_target: 50)
    @client.ad_costs.create!(
      platform: 'meta', name: 'Meta',
      start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 31), amount: 100
    )
    new_customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6))
    create_order(total_price: 100, customer: new_customer)

    result = call

    assert_equal 100.0, result[:cac].to_f
    assert_equal :over, result[:cac_target_status]
    assert_equal 50.0, result[:cac_target_diff].to_f
  end

  test 'tagged_revenue sums gross-minus-discounts only for orders matching the goal tag' do
    @client.goals.create!(year: 2026, month: 3, tagged_revenue_target: 100, tagged_revenue_tag: 'VendedoraElo')
    create_order(total_price: 150, tags: 'VendedoraElo, promo')
    create_order(total_price: 300, tags: 'outra-tag')

    result = call

    assert_equal 'VendedoraElo', result[:tagged_revenue_tag]
    assert_equal 150.0, result[:tagged_revenue].to_f
    assert_equal 150.0, result[:tagged_revenue_target_progress_pct]
  end

  test 'tagged_revenue accepts several comma-separated goal tags' do
    @client.goals.create!(year: 2026, month: 3, tagged_revenue_target: 500, tagged_revenue_tag: 'VendedoraElo, Eloina')
    create_order(total_price: 150, tags: 'VendedoraElo, promo')
    create_order(total_price: 200, tags: 'Eloina')
    create_order(total_price: 300, tags: 'outra-tag')

    assert_equal 350.0, call[:tagged_revenue].to_f
  end

  test 'tagged_revenue usa o total do relatório da Shopify quando disponível' do
    @client.goals.create!(year: 2026, month: 3, tagged_revenue_target: 1000, tagged_revenue_tag: 'VendedoraElo')
    fake = Struct.new(:total).new(BigDecimal('777.77'))
    Sales::ShopifyTaggedSales.stub(:new, fake) do
      result = Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 3).call
      assert_equal BigDecimal('777.77'), result[:tagged_revenue]
      assert_equal :shopify, result[:tagged_revenue_source]
    end
  end

  test 'tagged_revenue cai na soma dos pedidos e marca aproximado sem a Shopify' do
    @client.goals.create!(year: 2026, month: 3, tagged_revenue_target: 1000, tagged_revenue_tag: 'VendedoraElo')
    fake = Struct.new(:total).new(nil)
    Sales::ShopifyTaggedSales.stub(:new, fake) do
      result = Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 3).call
      assert_equal :approximate, result[:tagged_revenue_source]
    end
  end

  class FakeReport
    attr_reader :queries

    def initialize(sales:, sessions:)
      @sales = sales
      @sessions = sessions
      @queries = []
    end

    def rows(query)
      @queries << query
      query.start_with?('FROM sessions') ? @sessions : @sales
    end
  end

  test 'metas usam os números do relatório da Shopify quando disponível' do
    fake = FakeReport.new(
      sales: [{ 'total_sales' => '373854.23', 'gross_sales' => '490593.9', 'discounts' => '-61126.01',
                'returns' => '-66092.24', 'shipping_charges' => '10478.58', 'taxes' => '0', 'orders' => '805',
                'average_order_value' => '531.596', 'new_customers' => '589' }],
      sessions: [{ 'sessions' => '107367', 'conversion_rate' => '0.007115780453956989' }]
    )
    Sales::ShopifyReport.stub(:new, fake) do
      m = Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 10).call
      assert_equal :shopify, m[:metrics_source]
      assert_equal BigDecimal('373854.23'), m[:revenue]
      assert_equal BigDecimal('490593.9'), m[:gross_sales]
      assert_equal BigDecimal('61126.01'), m[:discounts]
      assert_equal BigDecimal('66092.24'), m[:returns]
      assert_equal BigDecimal('10478.58'), m[:shipping]
      assert_equal 805, m[:orders_count]
      assert_equal BigDecimal('531.60'), m[:avg_ticket]
      assert_equal 589, m[:new_customers_count]
      assert_equal 0.71, m[:conversion_rate]
    end
    assert(fake.queries.any? { |q| q.include?("TIMEZONE 'America/Sao_Paulo', CURRENCY 'BRL' SINCE 2026-10-01 UNTIL 2026-10-31") })
  end

  test 'filtro de tag entra na consulta de vendas da Shopify' do
    fake = FakeReport.new(sales: [{ 'total_sales' => '10', 'orders' => '1' }], sessions: nil)
    Sales::ShopifyReport.stub(:new, fake) do
      Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 10, tag: 'Eloina').call
    end
    assert(fake.queries.any? { |q| q.include?("WHERE order_tags CONTAINS 'VendedoraElo' OR order_tags CONTAINS 'Eloina'") })
  end

  test 'sem relatório da Shopify as metas usam os pedidos sincronizados' do
    fake = FakeReport.new(sales: nil, sessions: nil)
    Sales::ShopifyReport.stub(:new, fake) do
      m = Sales::MonthlyMetrics.new(client: @client, year: 2026, month: 10).call
      assert_equal :approximate, m[:metrics_source]
      assert_nil m[:returns]
    end
  end
end
