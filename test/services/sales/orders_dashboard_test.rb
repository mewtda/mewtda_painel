require 'test_helper'

class Sales::OrdersDashboardTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Pedidos', email: "ped-#{SecureRandom.hex(4)}@example.com")
  end

  def customer(state: nil)
    customer = Customer.create!(first_name: 'Ana', email: "#{SecureRandom.hex(4)}@example.com", shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, name: 'Ana', state:, refreshed_at: Time.current)
    customer
  end

  def order(at:, total:, customer: nil, shipping: 0, discount: 0, code: nil, cancelled: false, units: 1)
    o = Order.create!(client: @client, shopify_order_id: SecureRandom.hex(4), customer:, total_price: total,
                      total_shipping_price: shipping, total_discounts: discount, discount_code: code,
                      shopify_creation_date: at, cancelled_at: (cancelled ? at : nil))
    OrderItem.create!(order: o, sku: 'X', price: total, quantity: units)
    o
  end

  test 'kpis compare with the previous period and ignore cancelled orders' do
    ana = customer(state: 'sp')
    order(at: 40.days.ago, total: 100, customer: ana) # pedido antigo: Ana vira recorrente
    order(at: 2.days.ago, total: 300, customer: ana, shipping: 20, discount: 30, code: 'black10', units: 3)
    order(at: 3.days.ago, total: 100, customer: customer(state: 'RJ'))
    order(at: 3.days.ago, total: 999, cancelled: true)
    order(at: 10.days.ago, total: 200)

    d = Sales::OrdersDashboard.new(client: @client, preset: '7')

    assert_in_delta 400.0, d.kpis[:revenue][:value]
    assert_equal 2, d.kpis[:orders][:value]
    assert_in_delta 200.0, d.kpis[:average_ticket][:value]
    assert_in_delta 2.0, d.kpis[:items_per_order][:value]
    assert_in_delta 30.0, d.kpis[:discounts][:value]
    assert_equal 1, d.kpis[:cancelled][:value]
    assert_in_delta 100.0, d.kpis[:revenue][:change] # 400 x 200 no período anterior
    assert_equal 1, d.customers[:returning][:orders]
    assert_equal 1, d.customers[:new][:orders]
    assert_equal %w[SP RJ], d.states.map { |s| s[:state] }
    assert_equal [{ code: 'BLACK10', orders: 1, revenue: 300.0, discount: 30.0 }], d.coupons
    assert_in_delta 50.0, d.shipping[:free_share]
    assert_equal 2, d.by_hour.sum
    assert_equal 2, d.by_weekday.sum
    assert_equal 7, d.daily.size
    assert_in_delta 400.0, d.daily.sum { |row| row[:revenue] }
  end
end
