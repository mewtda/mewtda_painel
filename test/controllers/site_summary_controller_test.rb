require 'test_helper'

class SiteSummaryControllerTest < ActionDispatch::IntegrationTest
  def sign_in_client_user
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    client = Client.create!(name: 'Loja', email: "c-#{SecureRandom.hex(4)}@example.com")
    user = User.create!(name: 'User', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                        password_confirmation: 'password123', profile_id: Profile::USER, client: client)
    sign_in user
    client
  end

  test 'is the CRM home page' do
    sign_in_client_user
    get crm_path(p: '30')

    assert_response :success
    assert_includes response.body, 'Resumo do site'
    assert_includes response.body, 'Faturamento × investimento por dia'
  end

  test 'old tracking links are sent to the tracking dashboard' do
    sign_in_client_user
    get crm_path(period: '7')

    assert_redirected_to tracking_dashboard_path(period: '7')
  end
end
