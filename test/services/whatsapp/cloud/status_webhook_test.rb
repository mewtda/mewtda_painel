require 'test_helper'

class Whatsapp::Cloud::StatusWebhookTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @checkout = @client.abandoned_checkouts.create!(shopify_checkout_id: 'c1', phone: '+5511999999999',
                                                    checkout_created_at: Time.current,
                                                    first_notified_at: Time.current, whatsapp_message_id: 'wamid.A')
  end

  def payload(*statuses)
    { 'object' => 'whatsapp_business_account',
      'entry' => [{ 'changes' => [{ 'field' => 'messages', 'value' => { 'statuses' => statuses } }] }] }
  end

  def status(id, name, timestamp: Time.current.to_i, errors: nil)
    { 'id' => id, 'status' => name, 'timestamp' => timestamp.to_s, 'errors' => errors }.compact
  end

  test 'grava entregue e lida no checkout da mensagem' do
    Whatsapp::Cloud::StatusWebhook.process(payload(status('wamid.A', 'delivered')))
    assert_equal 'delivered', @checkout.reload.whatsapp_status

    Whatsapp::Cloud::StatusWebhook.process(payload(status('wamid.A', 'read')))
    assert_equal 'read', @checkout.reload.whatsapp_status
    assert_not_nil @checkout.whatsapp_status_at
  end

  test 'status atrasado não volta lida para entregue' do
    Whatsapp::Cloud::StatusWebhook.process(payload(status('wamid.A', 'read')))
    Whatsapp::Cloud::StatusWebhook.process(payload(status('wamid.A', 'delivered')))
    assert_equal 'read', @checkout.reload.whatsapp_status
  end

  test 'falha guarda o código e o motivo da Meta' do
    error = { 'code' => 131_049, 'title' => 'This message was not delivered to maintain healthy ecosystem engagement.',
              'error_data' => { 'details' => 'In order to maintain a healthy ecosystem engagement, the message failed to be delivered.' } }
    Whatsapp::Cloud::StatusWebhook.process(payload(status('wamid.A', 'failed', errors: [error])))

    @checkout.reload
    assert_equal 'failed', @checkout.whatsapp_status
    assert_match '131049', @checkout.whatsapp_error
    assert_match 'healthy ecosystem', @checkout.whatsapp_error
  end

  test 'atualiza destinatário de campanha pelo id da mensagem' do
    campaign = @client.campaigns.create!(name: 'Black')
    message = campaign.messages.create!(channel: 'whatsapp', status: 'sent')
    recipient = message.recipients.create!(campaign:, channel: 'whatsapp', phone: '+5511988887777', status: 'sent',
                                           provider_message_id: 'wamid.B')

    Whatsapp::Cloud::StatusWebhook.process(payload(status('wamid.B', 'delivered')))
    assert_equal 'delivered', recipient.reload.delivery_status
  end

  test 'ignora id desconhecido e payload sem status' do
    assert_nothing_raised do
      Whatsapp::Cloud::StatusWebhook.process(payload(status('wamid.Z', 'delivered')))
      Whatsapp::Cloud::StatusWebhook.process({ 'entry' => [{ 'changes' => [{ 'value' => { 'messages' => [] } }] }] })
      Whatsapp::Cloud::StatusWebhook.process({})
    end
    assert_nil @checkout.reload.whatsapp_status
  end
end
