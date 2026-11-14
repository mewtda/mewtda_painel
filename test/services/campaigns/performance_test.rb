require 'test_helper'

class Campaigns::PerformanceTest < ActiveSupport::TestCase
  SENT_AT = Time.zone.local(2026, 11, 10, 9, 0)

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def person(name, merged: [])
    customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6), first_name: name, email: "#{name}@example.com")
    CustomerProfile.create!(client: @client, customer:, name:, email: customer.email, refreshed_at: Time.current,
                            merged_customer_ids: merged)
    customer
  end

  def campaign(**attrs) = @client.campaigns.create!({ status: 'sent', started_at: SENT_AT, **attrs })

  def receive(campaign, customer, at: SENT_AT)
    campaign.recipients.create!(email: customer.email, customer_id: customer.id, status: 'sent', sent_at: at)
  end

  def order(customer, total, at, **attrs)
    Order.create!(client: @client, customer:, shopify_order_id: SecureRandom.hex(5), total_price: total,
                  shopify_creation_date: at, **attrs)
  end

  def result(*campaigns) = Campaigns::Performance.new(Campaign.where(id: campaigns.map(&:id))).call

  test 'sums reach and computes the investment from what was sent' do
    first = campaign(recipients_count: 100, blocked_count: 10, failed_count: 5, sent_count: 85)
    second = campaign(recipients_count: 50, blocked_count: 0, failed_count: 0, sent_count: 50)

    outcome = result(first, second)

    assert_equal [2, 150, 10, 5, 135], [outcome.campaigns_count, outcome.audience, outcome.blocked, outcome.failed, outcome.sent]
    assert_equal BigDecimal('0.54'), outcome.investment
    assert_in_delta 6.67, outcome.percent_of_audience(outcome.blocked), 0.01
  end

  test 'attributes orders placed within seven days after the e-mail and ignores the rest' do
    camp = campaign(recipients_count: 1, sent_count: 1)
    buyer = person('ana')
    receive(camp, buyer)
    order(buyer, 300, SENT_AT + 2.days)
    order(buyer, 100, SENT_AT - 1.hour)
    order(buyer, 200, SENT_AT + 8.days)
    order(buyer, 50, SENT_AT + 1.day, cancelled_at: Time.current)

    outcome = result(camp)

    assert_equal 1, outcome.purchases
    assert_equal 300, outcome.revenue
    assert_equal 300, outcome.avg_ticket
    assert_equal 300 - outcome.investment, outcome.net
  end

  test 'counts an order once even when the person is in two campaigns' do
    first = campaign(recipients_count: 1, sent_count: 1)
    second = campaign(recipients_count: 1, sent_count: 1)
    buyer = person('ana')
    receive(first, buyer)
    receive(second, buyer, at: SENT_AT + 1.day)
    order(buyer, 400, SENT_AT + 2.days)

    outcome = result(first, second)

    assert_equal [1, 400], [outcome.purchases, outcome.revenue]
  end

  test 'matches orders of merged duplicate customers' do
    camp = campaign(recipients_count: 1, sent_count: 1)
    duplicate = Customer.create!(shopify_customer_id: SecureRandom.hex(6), first_name: 'ana2', email: 'ana2@example.com')
    main = person('ana', merged: [duplicate.id])
    receive(camp, main)
    order(duplicate, 250, SENT_AT + 1.day)

    assert_equal 250, result(camp).revenue
  end

  test 'people who did not receive the e-mail do not generate revenue' do
    camp = campaign(recipients_count: 1, sent_count: 0)
    stranger = person('bia')
    camp.recipients.create!(email: stranger.email, customer_id: stranger.id, status: 'blocked')
    order(stranger, 500, SENT_AT + 1.day)

    assert_equal [0, 0], [result(camp).purchases, result(camp).revenue]
  end

  test 'engagement counts people once and groups opens and clicks by three hour buckets' do
    camp = campaign(recipients_count: 2, sent_count: 2)
    ana = person('ana')
    bia = person('bia')
    ana_row = receive(camp, ana)
    bia_row = receive(camp, bia)
    event = lambda do |recipient, type, hour|
      EmailEvent.create!(client: @client, source: 'campaign', campaign: camp, campaign_recipient: recipient, event_type: type,
                         ses_message_id: "m-#{recipient.id}", occurred_at: Time.utc(2026, 11, 10, hour, rand(60), rand(60)))
    end
    [ana_row, bia_row].each { |row| event.call(row, 'delivery', 12) }
    event.call(ana_row, 'open', 13)
    event.call(ana_row, 'open', 14)
    event.call(ana_row, 'click', 14)
    event.call(bia_row, 'bounce', 15)

    outcome = result(camp)

    assert outcome.tracked
    assert_equal [2, 1, 1, 1, 0], [outcome.delivered, outcome.opened, outcome.clicked, outcome.bounced, outcome.complaints]
    assert_equal 2, outcome.hours.values.sum
    assert_equal [0, 3, 6, 9, 12, 15, 18, 21], outcome.hours.keys
    assert_equal 50.0, outcome.rate(outcome.opened, outcome.delivered)
  end

  test 'engagement is not tracked without events' do
    camp = campaign(recipients_count: 1, sent_count: 1)

    outcome = result(camp)

    assert_not outcome.tracked
    assert_equal [0, 0, 0], [outcome.delivered, outcome.opened, outcome.hours.values.sum]
  end

  test 'returns zeros without campaigns' do
    outcome = Campaigns::Performance.new(Campaign.none).call

    assert_equal [0, 0, 0, 0], [outcome.campaigns_count, outcome.audience, outcome.purchases, outcome.revenue]
    assert_equal 0, outcome.percent_of_audience(3)
  end
end
