require 'test_helper'

class CampaignMessageTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @campaign = @client.campaigns.create!(name: 'Black')
  end

  test 'send_now / send_on / send_time compose send_at' do
    message = @campaign.messages.new(channel: 'email', send_now: '0', send_on: '2026-11-27', send_time: '10:30')
    message.valid?
    assert_equal Time.zone.local(2026, 11, 27, 10, 30), message.send_at
    message.assign_attributes(send_now: '1')
    message.valid?
    assert_nil message.send_at
  end

  test 'templates must belong to the store and match the channel' do
    other = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(3)}@example.com")
    foreign = other.whatsapp_templates.create!(label: 'X', body: 'Oi')
    refute @campaign.messages.new(channel: 'whatsapp', whatsapp_template: foreign).valid?
    refute @campaign.messages.new(channel: 'sms').valid?
  end

  test 'first_send_at and resume_at' do
    now = Time.zone.local(2026, 11, 16, 10, 0)
    message = @campaign.messages.new(channel: 'email', send_at: now + 2.days)
    assert_equal now + 2.days, message.first_send_at(now)
    message.send_at = nil
    assert_equal now, message.first_send_at(now)
    assert_equal Time.zone.local(2026, 11, 17, 8, 0), message.resume_at(now)
  end

  test 'recount! counts recipients by status' do
    message = @campaign.messages.create!(channel: 'whatsapp')
    message.recipients.create!(campaign: @campaign, channel: 'whatsapp', phone: '+5516990000001', status: 'sent')
    message.recipients.create!(campaign: @campaign, channel: 'whatsapp', phone: '+5516990000002', status: 'blocked')
    message.recount!
    assert_equal [1, 0, 1], [message.sent_count, message.failed_count, message.blocked_count]
  end

  test 'a whatsapp recipient needs a phone and an e-mail recipient needs an e-mail' do
    message = @campaign.messages.create!(channel: 'whatsapp')
    refute message.recipients.new(campaign: @campaign, channel: 'whatsapp').valid?
    refute message.recipients.new(campaign: @campaign, channel: 'email').valid?
  end
end
