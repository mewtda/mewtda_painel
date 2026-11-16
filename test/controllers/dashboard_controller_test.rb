require 'test_helper'

class DashboardControllerTest < ActionDispatch::IntegrationTest
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    profile = Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }
    @user = User.create!(name: 'Admin', email: "admin-#{SecureRandom.hex(4)}@example.com",
                         password: 'password123', password_confirmation: 'password123',
                         profile_id: profile.id, client: @client)
    sign_in @user
  end

  test 'opens without a period and asks the user to pick one' do
    get tracking_dashboard_path

    assert_response :success
    assert_match 'Escolha um período', response.body
    assert_no_match 'data-report-token', response.body
  end

  test 'with a period, renders the loading state with a signed token instead of querying' do
    get tracking_dashboard_path(period: '1')

    assert_response :success
    token = response.body[/data-report-token="([^"]+)"/, 1]
    report = Tracking::ReportToken.read(CGI.unescapeHTML(token))
    assert_equal({ 'user_id' => @user.id, 'client_id' => @client.id, 'period' => '1', 'year' => nil, 'month' => nil },
                 report)
  end
end
