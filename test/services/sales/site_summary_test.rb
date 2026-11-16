require 'test_helper'

class Sales::SiteSummaryTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Resumo', email: "res-#{SecureRandom.hex(4)}@example.com")
    @today = Time.zone.today
  end

  def order(at:, subtotal:, shipping: 0, cancelled: false)
    Order.create!(client: @client, shopify_order_id: SecureRandom.hex(4), subtotal_price: subtotal,
                  total_shipping_price: shipping, total_price: subtotal + shipping,
                  shopify_creation_date: at, cancelled_at: (cancelled ? at : nil))
  end

  test 'compares the period with the previous one and splits ad cost by day' do
    order(at: 1.day.ago, subtotal: 300, shipping: 20)
    order(at: 2.days.ago, subtotal: 180)
    order(at: 2.days.ago, subtotal: 999, cancelled: true)
    order(at: 10.days.ago, subtotal: 100)
    AdCost.create!(client: @client, platform: 'meta', name: 'Meta', start_date: @today - 6, end_date: @today, amount: 70)

    summary = Sales::SiteSummary.new(client: @client, preset: '7')

    assert_equal 7, summary.days.size
    assert_in_delta 500.0, summary.kpis[:revenue][:value]
    assert_equal 2, summary.kpis[:orders][:value]
    assert_in_delta 250.0, summary.kpis[:average_ticket][:value]
    assert_in_delta 70.0, summary.kpis[:ad_cost][:value]
    assert_in_delta 7.14, summary.kpis[:roas][:value]
    assert_in_delta 35.0, summary.kpis[:cpa][:value]
    assert_in_delta 400.0, summary.kpis[:revenue][:change]
    assert_equal 1, summary.cancelled_orders
    assert_in_delta 10.0, summary.daily.last[:ad_cost]
  end

  test 'accepts a custom range and ignores invalid dates' do
    summary = Sales::SiteSummary.new(client: @client, from: (@today - 2).iso8601, to: @today.iso8601)
    assert_equal 3, summary.days.size
    assert_nil summary.preset

    fallback = Sales::SiteSummary.new(client: @client, from: 'x', to: 'y')
    assert_equal '7', fallback.preset
  end
end
