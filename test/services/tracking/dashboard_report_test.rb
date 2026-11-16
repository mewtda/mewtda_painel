require 'test_helper'

class Tracking::DashboardReportTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja Funil', email: "funil-#{SecureRandom.hex(4)}@example.com")
    @pixel = IntegrationUser.create!(name: 'Pixel', slug: "pixel-#{SecureRandom.hex(4)}",
                                     api_secret: SecureRandom.hex(8), client: @client)
  end

  def event(kind, session, at: 1.hour.ago)
    ShopifyEvent.create!(client: @client, integration_user: @pixel, kind: kind, session_id: session, created_at: at)
  end

  test 'counts the funnel by session so every step uses the same base' do
    # 4 sessões; s1 navega muito (muitos eventos), mas conta uma vez por etapa.
    4.times { event('page_viewed', 's1') }
    3.times { event('product_viewed', 's1') }
    event('product_added_to_cart', 's1')
    event('checkout_started', 's1')
    event('checkout_completed', 's1')
    event('page_viewed', 's2')
    event('product_viewed', 's2')
    event('product_added_to_cart', 's2')
    event('page_viewed', 's3')
    event('product_viewed', 's3')
    event('page_viewed', 's4')
    Order.create!(client: @client, shopify_order_id: 'o1', total_price: 300, shopify_creation_date: 2.hours.ago)

    report = Tracking::DashboardReport.new(client: @client, period: '7').assigns
    funnel = report[:funnel].index_by { |step| step[:key] }

    assert_equal [4, 3, 2, 1, 1], report[:funnel].map { |step| step[:count] }
    assert_in_delta 75.0, funnel[:product][:pct_total]
    assert_in_delta 66.67, funnel[:cart][:pct_step]
    assert_equal 1, funnel[:checkout][:lost]
    assert_in_delta 25.0, report[:conversion_rate]
    assert_equal 1, report[:abandoned_carts]
    assert_in_delta 50.0, report[:abandoned_rate]
    assert_equal 1, report[:orders_summary][:count]
    assert_equal BigDecimal('75'), report[:orders_summary][:revenue_per_session]
  end
end
