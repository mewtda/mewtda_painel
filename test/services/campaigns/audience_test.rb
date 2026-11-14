require 'test_helper'

class AudienceTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def profile(email, state: nil)
    customer = Customer.create!(first_name: 'Cli', email:, shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, email:, email_marketing_state: state, refreshed_at: Time.current)
  end

  def everyone
    @client.segments.create!(name: 'Todos', kind: 'dynamic', rules: { 'groups' => [{ 'conditions' => [
                               { 'field' => 'orders_count', 'op' => 'gte', 'value' => '0' }
                             ] }] })
  end

  test 'counts recipients, leaves out suppressed and missing e-mails, and reports consent without blocking' do
    profile('a@example.com', state: 'subscribed')
    profile('b@example.com', state: 'not_subscribed')
    profile('c@example.com')
    profile('d@example.com', state: 'subscribed')
    profile(nil)
    @client.email_suppressions.create!(email: 'd@example.com', source: 'manual')

    result = Campaigns::Audience.new(@client, everyone).call

    assert_equal 5, result.total
    assert_equal 1, result.without_email
    assert_equal 1, result.suppressed
    assert_equal 3, result.recipients
    assert_equal 1, result.subscribed
    assert_equal 2, result.not_subscribed
  end

  test 'cost is price per thousand and the daily limit comes from the client plan' do
    @client.update!(daily_email_limit: 5000)
    2.times { |i| profile("p#{i}@example.com") }

    result = Campaigns::Audience.new(@client, everyone).call

    assert_equal BigDecimal('0.008'), result.cost
    assert_equal 5000, result.daily_limit
    assert_equal 0, result.used_today
  end

  test 'without a segment nobody receives' do
    result = Campaigns::Audience.new(@client, nil).call

    assert_equal 0, result.recipients
    assert_equal 0, result.cost
  end
end
