require 'test_helper'

class Sales::ShopifyReturnsTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Dunas', email: "d-#{SecureRandom.hex(4)}@example.com",
                             shopify_shop_url: 'dunas.myshopify.com', shopify_access_token: 'tok')
  end

  # O bloco devolve as linhas do relatório; aqui elas viram a resposta GraphQL da Shopify.
  def returns(tag: nil, &rows)
    runner = ->(q) { { 'data' => { 'shopifyqlQuery' => { 'parseErrors' => [], 'tableData' => { 'rows' => rows.call(q) } } } } }
    Sales::ShopifyReturns.new(client: @client, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31), tag: tag,
                              runner: runner).call
  end

  test 'lista os pedidos com devolução e soma' do
    queries = []
    result = returns do |q|
      queries << q
      [{ 'order_id' => '18964340408635', 'order_name' => 'DN378916469', 'returns' => '-9121.6' },
       { 'order_id' => '7708849602875', 'order_name' => '215543', 'returns' => '-2033.48' }]
    end

    assert_equal BigDecimal('11155.08'), result[:total]
    assert_equal 'DN378916469', result[:orders].first[:name]
    assert_equal BigDecimal('9121.6'), result[:orders].first[:returns]
    assert_equal 'https://admin.shopify.com/store/dunas/orders/18964340408635', result[:orders].first[:url]
    assert_includes queries.first, 'FROM sales SHOW returns GROUP BY order_id, order_name'
    assert_includes queries.first, 'HAVING returns < 0 SINCE 2026-10-01 UNTIL 2026-10-31'
    assert_equal queries.first, result[:query]
  end

  test 'filtro de tag entra na consulta' do
    queries = []
    returns(tag: 'Eloina') { |q| queries << q; [] }
    assert_includes queries.first, "WHERE order_tags CONTAINS 'VendedoraElo' OR order_tags CONTAINS 'Eloina'"
  end

  test 'sem relatório devolve nil' do
    assert_nil(returns { raise SocketError })
  end
end
