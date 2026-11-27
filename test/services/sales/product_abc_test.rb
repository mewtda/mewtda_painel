require 'test_helper'

class Sales::ProductAbcTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja ABC', email: "abc-#{SecureRandom.hex(4)}@example.com")
  end

  def product(name, shopify_id, sku)
    Product.create!(client: @client, shopify_product_name: name, shopify_product_id: shopify_id, sku:)
  end

  def sale(product, price, quantity: 1, at: 2.days.ago, cancelled: false)
    order = Order.create!(client: @client, shopify_order_id: SecureRandom.hex(4), shopify_creation_date: at,
                          cancelled_at: (cancelled ? at : nil))
    OrderItem.create!(order:, product:, sku: product.sku, price:, quantity:)
  end

  test 'classifies products by cumulative revenue and sums the variants of the same product' do
    vestido_p = product('Vestido', '100', 'VES-P')
    vestido_m = product('Vestido', '100', 'VES-M')
    blusa = product('Blusa', '200', 'BLU')
    saia = product('Saia', '300', 'SAI')
    meia = product('Meia', '400', 'MEI')
    product('Bolsa parada', '500', 'BOL')

    sale(vestido_p, 400, quantity: 1)
    sale(vestido_m, 400, quantity: 1) # Vestido: 800 (80%)
    sale(blusa, 150) # 15% -> acumulado 95%
    sale(saia, 40) # começa em 95% -> C
    sale(meia, 10)
    sale(meia, 999, cancelled: true)
    sale(blusa, 999, at: 200.days.ago)

    abc = Sales::ProductAbc.new(client: @client, preset: '90')

    assert_equal(%w[Vestido Blusa Saia Meia], abc.items.map(&:name))
    assert_equal(%w[A B C C], abc.items.map(&:curve))
    assert_in_delta 1000.0, abc.revenue
    assert_equal 2, abc.items.first.units
    assert_in_delta 80.0, abc.items.first.share
    assert_equal({ '100' => 'A', '200' => 'B', '300' => 'C', '400' => 'C' }, abc.curve_by_product_id)
    assert_equal 1, abc.summary['A'][:count]
    assert_in_delta 5.0, abc.summary['C'][:share_of_revenue]
    assert_equal 5, abc.catalog_count
    assert_equal 1, abc.unsold_count
    assert_equal 5, abc.orders_count
  end

  test 'the top product is always A, even when it alone passes 80%' do
    sale(product('Único', '1', 'U'), 100)

    assert_equal ['A'], Sales::ProductAbc.new(client: @client).items.map(&:curve)
  end
end
