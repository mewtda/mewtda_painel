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

  test 'shows the institutional page to a signed-out visitor' do
    get root_path

    assert_response :success
    assert_match 'Soluções para e-commerce', response.body
  end

  test 'shows the sales preview to a signed-in common user with a client' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get root_path

    assert_response :success
    assert_match "Olá, #{user.name}", response.body
    refute_match 'Gerencie seu negócio com inteligência', response.body
  end

  test 'shows the sales preview to a signed-in admin with a client' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    admin = build_user(admin: true, client: client)
    sign_in admin

    get root_path

    assert_response :success
    assert_match "Olá, #{admin.name}", response.body
  end

  test 'shows an empty-state message instead of charts when the signed-in user has no client' do
    admin = build_user(admin: true, client: nil)
    sign_in admin

    get root_path

    assert_response :success
    assert_match 'Nenhum cliente selecionado', response.body
  end

  test 'redirects a signed-in affiliate to events instead of showing the sales preview' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    affiliate = build_user(affiliate: true, client: client)
    sign_in affiliate

    get root_path

    assert_redirected_to events_path(utm_code: affiliate.utm_code)
  end

  test 'renders friendly empty-chart copy when the client has no orders this month' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get root_path

    assert_response :success
    assert_match 'esse gráfico ganha vida', response.body
  end

  test 'renders totals when the client has orders this month' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    Order.create!(
      client: client, shopify_order_id: SecureRandom.hex(6),
      shopify_creation_date: Time.current, total_price: 250, subtotal_price: 250, total_discounts: 0
    )
    sign_in user

    get root_path

    assert_response :success
    assert_match 'R$ 250,00', response.body
  end
end
