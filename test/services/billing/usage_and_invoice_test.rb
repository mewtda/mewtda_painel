require 'test_helper'

class Billing::UsageAndInvoiceTest < ActiveSupport::TestCase
  def build_client(**attrs)
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com", **attrs)
  end

  test 'email usage is tracked per day and the daily limit is enforced' do
    client = build_client(daily_email_limit: 2)
    usage = Billing::Usage.new(client)

    MessageUsage.track!(client, 'email')
    assert_not usage.limit_reached?('email')
    MessageUsage.track!(client, 'email')

    assert_equal 2, usage.today('email')
    assert usage.limit_reached?('email')
    assert_equal 1, MessageUsage.count
  end

  test 'no limit when the client has none' do
    client = build_client
    5.times { MessageUsage.track!(client, 'email') }

    assert_nil Billing::Usage.new(client).daily_limit('email')
    assert_not Billing::Usage.new(client).limit_reached?('email')
  end

  test 'daily series fills missing days with zero' do
    client = build_client
    MessageUsage.track!(client, 'email', 3)
    series = Billing::Usage.new(client).daily_series('email', days: 3)

    assert_equal [0, 0, 3], series.values
  end

  test 'invoice adds the plan price and R$ 4 per thousand emails of the month' do
    client = build_client(plan_name: 'Pro', plan_price: '297,00')
    MessageUsage.track!(client, 'email', 2_500)
    MessageUsage.track!(client, 'email', 999, day: Time.zone.today << 1)

    invoice = Billing::Invoice.new(client)

    assert_equal 'Pro', invoice.plan_name
    assert_equal BigDecimal('297'), invoice.plan_price
    assert_equal 2_500, invoice.emails_sent
    assert_equal BigDecimal('10'), invoice.emails_amount
    assert_equal BigDecimal('307'), invoice.total
  end

  test 'SES service stops at the daily email limit and counts sends' do
    client = build_client(daily_email_limit: 1, email_sending_domain: 'loja.com.br', ses_verification_status: 'verified')
    fake_ses = Minitest::Mock.new
    fake_ses.expect(:send_email, true) { true }
    service = Ses::SendEmailService.new(client, ses: fake_ses)

    assert service.call(to: 'a@example.com', subject: 'Oi', html_body: '<p>x</p>')
    assert_equal false, service.call(to: 'b@example.com', subject: 'Oi', html_body: '<p>x</p>')
    assert_equal 1, Billing::Usage.new(client).today('email')
    assert fake_ses.verify
  end
end
