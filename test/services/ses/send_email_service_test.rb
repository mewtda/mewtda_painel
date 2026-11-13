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
