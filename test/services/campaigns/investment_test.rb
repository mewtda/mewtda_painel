require 'test_helper'

class Campaigns::InvestmentTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'spent counts sent messages: panel fee plus estimated Meta fee for WhatsApp' do
    campaign = @client.campaigns.create!(name: 'Enviada', status: 'sent')
    campaign.messages.create!(channel: 'email', status: 'sent', sent_count: 1000)
    campaign.messages.create!(channel: 'whatsapp', status: 'sent', sent_count: 10)

    row = Campaigns::Investment.new(@client, [campaign]).for(campaign)

    assert_equal BigDecimal('5'), row.spent.panel # R$ 4 por mil e-mails + 10 x R$ 0,10
    assert_equal BigDecimal('3.2'), row.spent.meta # 10 x R$ 0,32
    assert_equal BigDecimal('8.2'), row.spent.total
    assert row.forecast.zero?
  end

  test 'forecast counts what is left of frozen messages and ignores finished ones' do
    campaign = @client.campaigns.create!(name: 'Enviando', status: 'sending')
    campaign.messages.create!(channel: 'whatsapp', status: 'sending', recipients_count: 100, sent_count: 60,
                              failed_count: 5, blocked_count: 5)
    campaign.messages.create!(channel: 'email', status: 'cancelled', recipients_count: 500)

    row = Campaigns::Investment.new(@client, [campaign]).for(campaign)

    assert_equal 30, row.forecast.whatsapps
    assert_equal 0, row.forecast.emails
    assert_equal 60, row.spent.whatsapps
  end

  test 'forecast of a message that has not started uses the current audience of its channel' do
    segment = @client.segments.create!(name: 'Todos', kind: 'static')
    2.times do |i|
      email = "#{SecureRandom.hex(4)}@example.com"
      customer = Customer.create!(first_name: 'C', email:, shopify_customer_id: SecureRandom.hex(6))
      CustomerProfile.create!(client: @client, customer:, name: 'C', email:, phone: "+55119999900#{i}#{i}",
                              refreshed_at: Time.current)
      SegmentMembership.create!(segment:, customer:)
    end
    campaign = @client.campaigns.create!(name: 'Agendada', status: 'scheduled', email_enabled: true,
                                         whatsapp_enabled: true)
    campaign.segments << segment
    campaign.messages.create!(channel: 'email', status: 'scheduled', send_at: 1.hour.from_now)
    campaign.messages.create!(channel: 'whatsapp', status: 'scheduled', send_at: 1.hour.from_now)

    investment = Campaigns::Investment.new(@client, [campaign])

    assert_equal 2, investment.for(campaign).forecast.emails
    assert_equal 2, investment.for(campaign).forecast.whatsapps
    assert_equal BigDecimal('0.848'), investment.forecast_total.total # 2 e-mails (0,008) + 2 x (0,10 + 0,32)
  end
end
