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
end
