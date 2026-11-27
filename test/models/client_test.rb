require 'test_helper'

class ClientTest < ActiveSupport::TestCase
  def build_client(overrides = {})
    Client.new({ name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com" }.merge(overrides))
  end

  test 'defaults to unverified email sending status' do
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    assert_equal 'unverified', client.ses_verification_status
    assert_not client.ses_domain_verified?
  end

  test 'rejects an invalid email_sending_domain' do
    client = build_client(email_sending_domain: 'not a domain')
    assert_not client.valid?
    assert_includes client.errors.attribute_names, :email_sending_domain
  end

  test 'accepts a valid email_sending_domain' do
    client = build_client(email_sending_domain: 'loja.com.br')
    assert client.valid?, client.errors.full_messages.to_s
  end

  test 'allows a blank email_sending_domain' do
    client = build_client(email_sending_domain: '')
    assert client.valid?
  end

  test 'ses_dns_records is empty without a domain or dkim tokens' do
    client = build_client
    assert_empty client.ses_dns_records
  end

  test 'ses_dns_records builds one CNAME entry per dkim token' do
    client = build_client(email_sending_domain: 'loja.com.br', ses_dkim_tokens: %w[abc def])

    records = client.ses_dns_records

    assert_equal 2, records.size
    assert_equal 'abc._domainkey.loja.com.br', records.first[:name]
    assert_equal 'CNAME', records.first[:type]
    assert_equal 'abc.dkim.amazonses.com', records.first[:value]
  end

  test 'ses_domain_verified? reflects ses_verification_status' do
    client = build_client(ses_verification_status: 'verified')
    assert client.ses_domain_verified?
  end

  test 'whatsapp_ready? com Evolution depende de número conectado' do
    client = Client.create!(name: 'Loja', email: "l-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    connection = client.whatsapp_connections.create!(name: 'A1')
    assert_not client.whatsapp_ready?

    connection.update!(state: 'connected', enabled: true)
    assert client.whatsapp_ready?

    connection.update!(enabled: false)
    assert_not client.reload.whatsapp_ready?
  end

  test 'todo cliente usa a Evolution Mewtda' do
    assert build_client.whatsapp_evolution?
    assert_not build_client.whatsapp_ready?
  end

  test 'destroy removes the store data that points to the client' do
    client = Client.create!(name: 'Loja Fim', email: "fim-#{SecureRandom.hex(4)}@example.com")
    product = Product.create!(client:, shopify_product_name: 'Vestido', shopify_product_id: '1', sku: 'V')
    landing = client.landing_pages.create!(name: 'Drop', slug: "drop-#{SecureRandom.hex(3)}", template: 'drop_01_1822')
    order = Order.create!(client:, shopify_order_id: '1', shopify_creation_date: Time.current, landing_page: landing)
    OrderItem.create!(order:, product:, sku: 'V', price: 10, quantity: 1)
    integration_user = IntegrationUser.create!(client:, name: 'Site', slug: 'site')
    campaign = client.campaigns.create!(name: 'Black')
    EmailEvent.create!(client:, campaign:, event_type: 'delivery', source: 'campaign', ses_message_id: 'm1',
                       occurred_at: Time.current)

    client.destroy!

    assert_not Client.exists?(client.id)
    assert_not Order.exists?(order.id)
    assert_not Product.exists?(product.id)
    assert_not IntegrationUser.exists?(integration_user.id)
  end
end
