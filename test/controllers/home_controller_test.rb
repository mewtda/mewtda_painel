require 'test_helper'

class HomeControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, affiliate: false, client: nil)
    profile_id =
      if admin then Profile::ADMIN
      elsif affiliate then Profile::AFFILIATE
      else Profile::USER
      end
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = profile_id.to_s }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'the old /site address goes to the landing at the root' do
    get '/site'

    assert_redirected_to '/'
  end

  test 'shows the institutional page to a signed-out visitor' do
    get root_path

    assert_response :success
    assert_match 'Soluções para e-commerce', response.body
  end

  test 'sends a signed-in user from the root to the panel' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in build_user(client: client)

    get root_path

    assert_redirected_to crm_path
  end

  test 'sends a signed-in admin without a client from the root to the panel' do
    sign_in build_user(admin: true, client: nil)

    get root_path

    assert_redirected_to crm_path
  end

  test 'redirects a signed-in affiliate to events instead of showing the sales preview' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    affiliate = build_user(affiliate: true, client: client)
    sign_in affiliate

    get root_path

    assert_redirected_to events_path(utm_code: affiliate.utm_code)
  end
end
