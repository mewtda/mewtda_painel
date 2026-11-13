require 'test_helper'

class AccountLimitsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             plan_name: 'Pro', plan_price: 297, daily_email_limit: 1000)
    sign_in User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
  end

  test 'limits shows the meters without prices' do
    MessageUsage.track!(@client, 'email', 120)

    get limits_account_path

    assert_response :success
    assert_match 'Meus limites', response.body
    assert_match '120', response.body
    assert_no_match 'R$', response.body
  end

  test 'invoice shows plan and email usage' do
    MessageUsage.track!(@client, 'email', 1000)

    get invoice_account_path

    assert_response :success
    assert_match 'Plano Pro', response.body
    assert_match 'R$ 297,00', response.body
    assert_match 'R$ 4,00', response.body
    assert_match 'R$ 301,00', response.body
  end

  test 'account edit shows the tabs' do
    get edit_account_path

    assert_response :success
    assert_match 'Meus limites', response.body
    assert_match 'Fatura', response.body
  end
end
