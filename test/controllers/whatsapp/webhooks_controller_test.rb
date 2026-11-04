require 'test_helper'

class Whatsapp::WebhooksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @client = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    @connection = @client.whatsapp_connections.create!(name: 'A1')
  end

  def payload(instance: @connection.instance_key)
    { event: 'messages.upsert', instance: instance, date_time: Time.current.iso8601,
      data: { key: { id: 'webhook-1', remoteJid: '5511988887777@s.whatsapp.net', fromMe: false },
              message: { conversation: 'Oi' }, messageTimestamp: Time.current.to_i } }
  end

  def send_webhook(body: payload, token: @connection.webhook_token)
    post "/whatsapp/webhooks/#{@connection.instance_key}", params: body,
         headers: { 'X-Mewtda-Webhook-Token' => token }, as: :json
  end

  test 'token errado é recusado' do
    send_webhook(token: 'x' * 64)

    assert_response :unauthorized
    assert_equal 0, @connection.events.count
  end

  test 'instance divergente é recusada' do
    send_webhook(body: payload(instance: 'mewtda-outra'))

    assert_response :unprocessable_entity
    assert_equal 0, @connection.events.count
  end

  test 'evento válido é aceito e registrado' do
    send_webhook

    assert_response :accepted
    assert_equal 1, @connection.events.count
    assert_equal 'messages.upsert', @connection.events.last.kind
  end

  test 'mesmo payload duas vezes gera um só evento' do
    body = payload
    2.times do
      send_webhook(body: body)
      assert_response :accepted
    end

    assert_equal 1, @connection.events.count
  end
end
