require 'test_helper'

class Sales::AbandonedCheckoutMetricsTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @from = 30.days.ago
    @to = Time.current
  end

  def checkout(price, at: 1.day.ago, completed_at: nil, client: @client)
    AbandonedCheckout.create!(client: client, shopify_checkout_id: SecureRandom.hex(6),
                              total_price: price, checkout_created_at: at, completed_at: completed_at)
  end

  def call = Sales::AbandonedCheckoutMetrics.new(@client, from: @from, to: @to).call

  test 'computes count, average ticket, totals and recovered values' do
    checkout(100)
    checkout(200)
    checkout(300, completed_at: 1.hour.ago)

    result = call

    assert_equal 3, result[:count]
    assert_equal BigDecimal('200'), result[:average_ticket]
    assert_equal BigDecimal('600'), result[:total]
    assert_equal 1, result[:recovered_count]
    assert_equal BigDecimal('300'), result[:recovered_total]
  end

  test 'ignores checkouts outside the period and from other clients' do
    checkout(100)
    checkout(900, at: 60.days.ago)
    other = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(4)}@example.com")
    checkout(500, client: other)

    result = call

    assert_equal 1, result[:count]
    assert_equal BigDecimal('100'), result[:total]
  end

  test 'average ticket is zero without checkouts and rounds to 2 places' do
    assert_equal 0, call[:average_ticket]
    checkout(10)
    checkout(10)
    checkout(10.01)
    assert_equal BigDecimal('10.0'), call[:average_ticket].round(1)
    assert_equal call[:average_ticket], call[:average_ticket].round(2)
  end
end
