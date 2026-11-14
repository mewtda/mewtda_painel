require 'test_helper'

class Ses::SendEmailServiceTest < ActiveSupport::TestCase
  def build_client(verified: true)
    Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      email_sending_domain: 'loja.com.br', ses_verification_status: verified ? 'verified' : 'pending'
    )
  end

  test 'sends through SES using the client sending domain and returns true' do
    fake_ses = Minitest::Mock.new
    fake_ses.expect(:send_email, true) do |args|
      args[:from_email_address].end_with?('@loja.com.br>') &&
        args[:destination][:to_addresses] == ['ana@example.com'] &&
        args[:content][:simple][:subject][:data] == 'Assunto' &&
        args[:content][:simple][:body][:html][:data] == '<p>Corpo</p>'
    end

    result = Ses::SendEmailService.new(build_client, ses: fake_ses).call(
      to: 'ana@example.com', subject: 'Assunto', html_body: '<p>Corpo</p>'
    )

    assert result
    fake_ses.verify
  end

  test 'returns false without calling SES when the domain is not verified' do
    fake_ses = Minitest::Mock.new

    result = Ses::SendEmailService.new(build_client(verified: false), ses: fake_ses).call(
      to: 'ana@example.com', subject: 'Assunto', html_body: '<p>Corpo</p>'
    )

    assert_equal false, result
  end

  test 'tools fall back to the shared CRM domain only when it is configured' do
    client = build_client(verified: false)
    send_to = lambda do |shared_domain|
      ENV['SHARED_EMAIL_DOMAIN'] = shared_domain
      fake_ses = Minitest::Mock.new
      fake_ses.expect(:send_email, true) { |args| args[:from_email_address].end_with?('@avisos.crm.com.br>') } if shared_domain
      result = Ses::SendEmailService.new(client, ses: fake_ses, shared: true).call(to: 'ana@example.com', subject: 'A', html_body: 'B')
      fake_ses.verify
      result
    end

    assert_equal false, send_to.call(nil)
    assert send_to.call('avisos.crm.com.br')
  ensure
    ENV.delete('SHARED_EMAIL_DOMAIN')
  end

  test 'campaign sending never uses the shared CRM domain' do
    ENV['SHARED_EMAIL_DOMAIN'] = 'avisos.crm.com.br'

    result = Ses::SendEmailService.new(build_client(verified: false), ses: Minitest::Mock.new).call(
      to: 'ana@example.com', subject: 'A', html_body: 'B'
    )

    assert_equal false, result
  ensure
    ENV.delete('SHARED_EMAIL_DOMAIN')
  end

  test 'sends the configuration set and tags only when tracking is configured and tags are given' do
    ENV['SES_CONFIGURATION_SET'] = 'mewtda-crm-eventos'
    client = build_client
    sent = []
    fake_ses = Object.new
    fake_ses.define_singleton_method(:send_email) { |args| sent << args }
    service = Ses::SendEmailService.new(client, ses: fake_ses)

    service.call(to: 'ana@example.com', subject: 'A', html_body: 'B', tags: { source: 'campaign', campaign_id: 7 })
    service.call(to: 'ana@example.com', subject: 'A', html_body: 'B')

    assert_equal 'mewtda-crm-eventos', sent.first[:configuration_set_name]
    assert_equal({ 'source' => 'campaign', 'campaign_id' => '7', 'client_id' => client.id.to_s },
                 sent.first[:email_tags].to_h { |tag| [tag[:name], tag[:value]] })
    assert_not sent.last.key?(:configuration_set_name)

    ENV.delete('SES_CONFIGURATION_SET')
    service.call(to: 'bia@example.com', subject: 'A', html_body: 'B', tags: { source: 'campaign' })
    assert_not sent.last.key?(:email_tags)
  ensure
    ENV.delete('SES_CONFIGURATION_SET')
  end

  test 'returns false without calling SES when the recipient is on the refusal list' do
    client = build_client
    EmailSuppression.unsubscribe!(client, 'Ana@Example.com')
    fake_ses = Minitest::Mock.new

    result = Ses::SendEmailService.new(client, ses: fake_ses).call(
      to: 'ana@example.com', subject: 'Assunto', html_body: '<p>Corpo</p>'
    )

    assert_equal false, result
    assert fake_ses.verify
  end

  test 'adds one-click List-Unsubscribe headers when an unsubscribe url is given' do
    fake_ses = Minitest::Mock.new
    fake_ses.expect(:send_email, true) do |args|
      args[:content][:simple][:headers] == [
        { name: 'List-Unsubscribe', value: '<https://www.mewtda.com.br/widget/descadastrar/abc>' },
        { name: 'List-Unsubscribe-Post', value: 'List-Unsubscribe=One-Click' }
      ]
    end

    Ses::SendEmailService.new(build_client, ses: fake_ses).call(
      to: 'ana@example.com', subject: 'Assunto', html_body: '<p>Corpo</p>',
      unsubscribe_url: 'https://www.mewtda.com.br/widget/descadastrar/abc'
    )

    assert fake_ses.verify
  end
end
