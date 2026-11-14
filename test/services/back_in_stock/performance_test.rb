require 'test_helper'

class BackInStock::PerformanceTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 14)
  NOW = Time.zone.local(2026, 11, 14, 12, 0)

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @period = Campaigns::Period.new('custom', '2026-11-01', '2026-11-14', today: TODAY)
    @variant = Product.create!(client: @client, shopify_product_name: 'Vestido', shopify_variant_id: '555', sku: 'V1', price: 300)
  end

  def alert(email: 'ana@example.com', variant: 555, created: NOW - 5.days, status: 'pending', notified: nil, **attrs)
    BackInStockAlert.create!(client: @client, shopify_product_id: 1, shopify_variant_id: variant, product_handle: 'vestido',
                             product_title: 'Vestido', variant_title: 'P', email:, status:, created_at: created,
                             notified_at: notified, price: 300, **attrs)
  end

  def buyer(email, product: @variant, at: NOW, total: 400)
    customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6), first_name: email, email:)
    CustomerProfile.find_or_create_by!(client: @client, customer:) do |profile|
      profile.assign_attributes(name: email, email:, refreshed_at: Time.current)
    end
    order = Order.create!(client: @client, customer:, shopify_order_id: SecureRandom.hex(5), total_price: total, shopify_creation_date: at)
    OrderItem.create!(order:, product:, sku: product.sku, quantity: 1, price: 300)
    order
  end

  def result(period = @period, sort: 'demand') = BackInStock::Performance.new(@client, period, sort:).call

  test 'counts requests, distinct variants and notifications of the period' do
    alert(email: 'a@example.com')
    alert(email: 'b@example.com')
    alert(email: 'c@example.com', variant: 777)
    alert(email: 'd@example.com', created: NOW - 40.days)
    alert(email: 'e@example.com', status: 'notified', notified: NOW - 1.day)

    totals = result.totals

    assert_equal [4, 2, 1], [totals.requests, totals.variants, totals.notified]
  end

  test 'attributes purchases of the same e-mail and variant within seven days after the notice' do
    alert(status: 'notified', notified: NOW - 3.days)
    buyer('ana@example.com', at: NOW - 2.days, total: 400)
    buyer('ana@example.com', at: NOW - 2.hours, total: 50)
    other = Product.create!(client: @client, shopify_product_name: 'Outro', shopify_variant_id: '999', sku: 'O1', price: 10)
    buyer('ana@example.com', product: other, at: NOW - 1.day, total: 999)
    buyer('zoe@example.com', at: NOW - 1.day, total: 777)

    totals = result.totals

    assert_equal [2, 450], [totals.purchases, totals.revenue]
  end

  test 'ignores purchases before the notice, after the window and cancelled orders' do
    alert(status: 'notified', notified: NOW - 3.days)
    buyer('ana@example.com', at: NOW - 4.days)
    late = alert(email: 'bia@example.com', status: 'notified', notified: NOW - 12.days, created: NOW - 13.days)
    buyer('bia@example.com', at: late.notified_at + 8.days)
    buyer('ana@example.com', at: NOW - 1.day).update!(cancelled_at: Time.current)

    assert_equal [0, 0], [result.totals.purchases, result.totals.revenue]
  end

  test 'funnel splits waiting, notified, ordered and cancelled requests' do
    alert(email: 'w@example.com')
    alert(email: 'c@example.com', status: 'cancelled')
    alert(email: 'n@example.com', status: 'notified', notified: NOW - 3.days)
    alert(email: 'ana@example.com', status: 'notified', notified: NOW - 3.days)
    buyer('ana@example.com', at: NOW - 2.days)

    assert_equal({ waiting: 1, notified: 1, ordered: 1, cancelled: 1 }, result.funnel)
    assert_equal 50.0, result.conversion
  end

  test 'compares with the previous period of the same size' do
    alert(email: 'a@example.com')
    alert(email: 'b@example.com')
    alert(email: 'old@example.com', created: NOW - 20.days)

    outcome = result

    assert_equal 1, outcome.previous.requests
    assert_equal 100.0, outcome.change(:requests)
    assert_nil outcome.change(:revenue)
  end

  test 'the all time period has no previous comparison' do
    alert

    outcome = result(Campaigns::Period.new('all', nil, nil, today: TODAY))

    assert_nil outcome.previous
    assert_nil outcome.change(:requests)
  end

  test 'daily series are filled with zeros across the period' do
    alert(created: Time.zone.local(2026, 11, 10, 10, 0))

    series = result.requests_by_day

    assert_equal 14, series.size
    assert_equal 1, series[Date.new(2026, 11, 10)]
    assert_equal 0, series[Date.new(2026, 11, 11)]
  end

  test 'age buckets and averages come from the waiting requests' do
    alert(email: 'a@example.com', created: Time.current - 1.day)
    alert(email: 'b@example.com', created: Time.current - 20.days)
    alert(email: 'c@example.com', created: Time.current - 120.days)

    outcome = result

    assert_equal([1, 0, 1, 0, 1], outcome.age_buckets.map { |bucket| bucket[:count] })
    assert_in_delta 47, outcome.avg_age_days, 0.1
  end

  test 'average time to notify is measured from the request to the notice' do
    alert(status: 'notified', created: NOW - 12.days, notified: NOW - 2.days)

    assert_in_delta 10, result.avg_notify_days, 0.01
  end

  test 'top variants follow the chosen sort and carry the all time history' do
    2.times { |index| alert(email: "m#{index}@example.com", variant: 555) }
    alert(email: 'x@example.com', variant: 777, status: 'notified', notified: NOW - 1.day)
    alert(email: 'y@example.com', variant: 777)

    outcome = result

    assert_equal [555, 777], outcome.top_variants.map(&:shopify_variant_id)
    assert_equal 2, outcome.history[777]
  end

  test 'notifications carry the delivery events recorded for them' do
    sent = alert(status: 'notified', notified: NOW - 1.day)
    %w[delivery open click].each do |type|
      EmailEvent.create!(client: @client, source: 'back_in_stock', back_in_stock_alert: sent, event_type: type,
                         ses_message_id: 'm-1', occurred_at: NOW)
    end
    alert(email: 'plain@example.com', status: 'notified', notified: NOW - 2.days)

    pairs = result.notifications

    assert_equal([%w[click delivery open], []], pairs.map { |_, events| events.sort })
  end

  test 'other stores never leak into the numbers' do
    other = Client.create!(name: 'Outra', email: "outra-#{SecureRandom.hex(4)}@example.com")
    BackInStockAlert.create!(client: other, shopify_product_id: 1, shopify_variant_id: 555, product_handle: 'v',
                             email: 'z@example.com', created_at: NOW - 1.day)

    assert_equal 0, result.totals.requests
  end
end
