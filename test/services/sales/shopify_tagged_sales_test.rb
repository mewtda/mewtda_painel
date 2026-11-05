require 'test_helper'

class Sales::ShopifyTaggedSalesTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Dunas', email: "d-#{SecureRandom.hex(4)}@example.com",
                             shopify_shop_url: 'dunas.myshopify.com', shopify_access_token: 'tok')
  end

  def service(tags = 'VendedoraElo', runner:)
    Sales::ShopifyTaggedSales.new(client: @client, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31),
                                  tags: tags, runner: runner)
  end

  def ok_body
    { 'data' => { 'shopifyqlQuery' => { 'parseErrors' => [], 'tableData' => { 'rows' => [
      { 'order_tag' => 'VendedoraElo', 'total_sales' => '17246.84', 'total_sales__totals' => '29307.96' },
      { 'order_tag' => 'Eloina', 'total_sales' => '12061.12', 'total_sales__totals' => '29307.96' }
    ] } } } }
  end

  test 'devolve o total da Shopify para as tags do grupo' do
    queries = []
    total = service(runner: ->(q) { queries << q; ok_body }).total

    assert_equal BigDecimal('29307.96'), total
    assert_includes queries.first, "order_tags CONTAINS 'VendedoraElo' OR order_tags CONTAINS 'Eloina'"
    assert_includes queries.first, "HAVING order_tag IN ('VendedoraElo', 'Eloina')"
    assert_includes queries.first, "TIMEZONE 'America/Sao_Paulo', CURRENCY 'BRL'"
    assert_includes queries.first, 'SINCE 2026-10-01 UNTIL 2026-10-31'
  end

  test 'sem pedidos no período devolve zero' do
    body = { 'data' => { 'shopifyqlQuery' => { 'parseErrors' => [], 'tableData' => { 'rows' => [] } } } }
    assert_equal 0, service(runner: ->(_) { body }).total
  end

  test 'erro da API ou de parse devolve nil' do
    assert_nil service(runner: ->(_) { { 'errors' => [{ 'message' => 'Access denied' }] } }).total
    parse = { 'data' => { 'shopifyqlQuery' => { 'parseErrors' => ['x'], 'tableData' => nil } } }
    assert_nil service(runner: ->(_) { parse }).total
    assert_nil service(runner: ->(_) { raise SocketError }).total
  end

  test 'tags com aspas ou caracteres estranhos não entram na consulta' do
    queries = []
    service("Loja'x", runner: ->(q) { queries << q; ok_body }).total
    assert_empty queries
  end
end
