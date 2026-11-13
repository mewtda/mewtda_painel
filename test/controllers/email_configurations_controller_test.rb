require 'test_helper'

class EmailConfigurationsControllerTest < ActionDispatch::IntegrationTest
  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::USER, client: client
    )
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'edit shows the current domain configuration' do
    client = build_client
    sign_in build_user(client: client)

    get edit_email_configuration_path

    assert_response :success
  end

  test 'update saves the domain and creates the SES identity' do
    client = build_client
    sign_in build_user(client: client)
    fake_service = Minitest::Mock.new
    fake_service.expect(:register!, true, ['loja.com.br'])

    Ses::DomainIdentityService.stub :new, fake_service do
      patch email_configuration_path, params: { client: { email_sending_domain: 'loja.com.br' } }
    end

    assert_redirected_to edit_email_configuration_path
    fake_service.verify
  end

  test 'update re-renders the form when the domain is invalid' do
    sign_in build_user(client: build_client)

    patch email_configuration_path, params: { client: { email_sending_domain: 'not a domain' } }

    assert_response :unprocessable_entity
  end

  test 'refresh_status checks SES and redirects back' do
    client = build_client
    client.update!(email_sending_domain: 'loja.com.br', ses_dkim_tokens: %w[a b c],
                    ses_verification_status: 'pending')
    sign_in build_user(client: client)
    fake_service = Minitest::Mock.new
    fake_service.expect(:refresh_status!, 'pending')

    Ses::DomainIdentityService.stub :new, fake_service do
      post refresh_email_configuration_path
    end

    assert_redirected_to edit_email_configuration_path
    fake_service.verify
  end
end
