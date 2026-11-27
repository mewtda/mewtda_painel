require 'test_helper'

class Webhooks::WhatsappCloudControllerTest < ActionDispatch::IntegrationTest
  SECRET = 'segredo-do-app'.freeze
  VERIFY = 'token-de-verificacao'.freeze

  def with_env(&)
    saved = ENV.values_at('META_APP_SECRET', 'WHATSAPP_WEBHOOK_VERIFY_TOKEN')
    ENV['META_APP_SECRET'] = SECRET
    ENV['WHATSAPP_WEBHOOK_VERIFY_TOKEN'] = VERIFY
    yield
  ensure
    ENV['META_APP_SECRET'], ENV['WHATSAPP_WEBHOOK_VERIFY_TOKEN'] = saved
  end

  def signed_post(body, secret: SECRET)
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, body)}"
    post whatsapp_cloud_webhook_path, params: body,
                                      headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => signature }
  end

  test 'verificação da Meta devolve o challenge com o token certo' do
    with_env do
      get whatsapp_cloud_webhook_path, params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => VERIFY,
                                                 'hub.challenge' => '12345' }
      assert_response :success
      assert_equal '12345', response.body

      get whatsapp_cloud_webhook_path, params: { 'hub.mode' => 'subscribe', 'hub.verify_token' => 'errado',
                                                 'hub.challenge' => '12345' }
      assert_response :forbidden
    end
  end

  test 'aceita status assinado e atualiza o checkout' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    checkout = client.abandoned_checkouts.create!(shopify_checkout_id: 'c1', phone: '+5511999999999',
                                                  checkout_created_at: Time.current, whatsapp_message_id: 'wamid.A')
    body = { entry: [{ changes: [{ value: { statuses: [{ id: 'wamid.A', status: 'delivered',
                                                         timestamp: Time.current.to_i.to_s }] } }] }] }.to_json

    with_env { signed_post(body) }

    assert_response :success
    assert_equal 'delivered', checkout.reload.whatsapp_status
  end

  test 'recusa assinatura inválida' do
    with_env { signed_post('{"entry":[]}', secret: 'outro') }
    assert_response :forbidden
  end
end
