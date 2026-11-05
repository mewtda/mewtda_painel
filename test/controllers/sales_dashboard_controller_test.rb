require 'test_helper'

class SalesDashboardControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    # No profiles.yml fixture exists, so the referenced profile (id 1 = admin,
    # id 2 = regular user, per Profile::ADMIN/Profile::USER) must be created
    # here to satisfy the users.profile_id foreign key constraint.
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'redirects a non-admin user without a client' do
    user = build_user
    sign_in user

    get sales_dashboard_path

    assert_redirected_to crm_path
  end

  test 'allows a non-admin client user' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path

    assert_response :success
  end

  test 'always allows an admin regardless of client' do
    admin = build_user(admin: true)
    sign_in admin

    get sales_dashboard_path

    assert_response :success
  end

  test 'renders the metrics for the requested month' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6),
                  shopify_creation_date: Time.zone.local(2026, 3, 10),
                  total_price: 250, subtotal_price: 250, total_discounts: 0)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'R$ 250,00', response.body
  end

  test 'shows a not-registered warning when the client has ad costs but not for this period' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    client.ad_costs.create!(
      platform: 'meta', name: 'Campanha Fevereiro',
      start_date: Date.new(2026, 2, 1), end_date: Date.new(2026, 2, 28), amount: 100
    )
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'Nenhum custo de anúncio cadastrado para este período', response.body
  end

  test 'shows a no-cost warning when no ad cost was ever registered for the client' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match 'Nenhum custo de anúncio cadastrado para este cliente', response.body
  end

  test 'the no-cost warning links to the ad cost registration screen' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 3)

    assert_response :success
    assert_match %r{href="#{Regexp.escape(new_ad_cost_path)}"}, response.body
  end

  test 'blocks a non-admin from triggering sync_ad_costs even when the dashboard is enabled' do
    client = Client.create!(
      name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
      meta_access_token: 'token', meta_ad_account_id: 'act_1'
    )
    user = build_user(client: client)
    sign_in user

    post sync_ad_costs_sales_dashboard_path

    assert_redirected_to crm_path
  end

  test 'does not crash on an out-of-range month param' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get sales_dashboard_path(year: 2026, month: 99)

    assert_response :success
  end

  test 'orders_for_day returns only the orders created on the requested local day' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    # 23:39 em Brasília (-03:00) cai em 2026-03-15 no calendário local, mesmo
    # armazenado como "2026-03-16 02:39" (UTC-equivalente) no banco.
    Order.create!(client: client, shopify_order_id: SecureRandom.hex(6), shopify_order_number: '1001',
                  shopify_creation_date: Time.zone.local(2026, 3, 15, 23, 39),
                  total_price: 300, subtotal_price: 300, total_discounts: 0)
    sign_in user

    get orders_for_day_sales_dashboard_path(year: 2026, month: 3, day: 15)
    body15 = JSON.parse(response.body)

    get orders_for_day_sales_dashboard_path(year: 2026, month: 3, day: 16)
    body16 = JSON.parse(response.body)

    assert_equal 1, body15['orders'].size
    assert_equal '1001', body15['orders'].first['number']
    assert_equal 0, body16['orders'].size
  end

  test 'mostra o botão de copiar a consulta da Shopify ao lado das métricas' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user
    report = Object.new
    def report.rows(query)
      query.start_with?('FROM sessions') ? [{ 'conversion_rate' => '0.01' }] : [{ 'total_sales' => '100', 'orders' => '1' }]
    end

    Sales::ShopifyReport.stub(:new, report) do
      get sales_dashboard_path(year: 2026, month: 3)
    end

    assert_response :success
    assert_select 'button.sd-copy-query[data-query^="FROM sales SHOW total_sales"]'
    assert_match 'Números do relatório da Shopify', response.body
  end
end
