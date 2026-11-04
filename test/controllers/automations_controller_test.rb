require 'test_helper'

class AutomationsControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'redirects when no client is linked or selected' do
    user = build_user
    sign_in user

    get automations_path

    assert_redirected_to crm_path
  end

  test 'allows a non-admin client user' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get automations_path

    assert_response :success
  end

  test 'allows an admin via the selected client in session' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    admin = build_user(admin: true)
    sign_in admin

    post update_selected_client_path, params: { client_id: client.id }
    get automations_path

    assert_response :success
  end

  test 'edit_tracking initializes a not-yet-persisted campaign with tracking defaults' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_tracking_automation_path

    assert_response :success
    assert_equal 0, client.campaigns.count
  end

  test 'update_tracking creates the shipping_tracking campaign' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch tracking_automation_path, params: {
      campaign: {
        name: 'Rastreio', message: 'Seu pedido {pedido} saiu, rastreio: {rastreio}',
        start_date: Date.current, end_date: Date.current + 1.year,
        active: '1', max_sends: 3, interval_days: 4
      }
    }

    assert_redirected_to automations_path
    campaign = client.campaigns.find_by(kind: 'shipping_tracking')
    assert campaign.present?
    assert campaign.active?
  end

  test 'edit_cashback initializes a not-yet-persisted campaign with cashback defaults' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_cashback_automation_path

    assert_response :success
    assert_equal 0, client.campaigns.count
  end

  test 'update_cashback creates the cashback campaign' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch cashback_automation_path, params: {
      campaign: {
        name: 'Cashback', message: 'Oi {nome}, use {cupom}!',
        start_date: Date.current, end_date: Date.current + 1.year,
        active: '1', days_after_purchase: 7
      }
    }

    assert_redirected_to automations_path
    campaign = client.campaigns.find_by(kind: 'cashback')
    assert campaign.present?
    assert campaign.active?
    assert_equal 7, campaign.days_after_purchase
  end

  test 'edit_cart_recovery initializes a not-yet-persisted campaign with defaults' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_cart_recovery_automation_path

    assert_response :success
    assert_equal 0, client.campaigns.count
  end

  test 'update_cart_recovery creates the cart_recovery campaign with resend config' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch cart_recovery_automation_path, params: {
      campaign: {
        name: 'Recuperação de Carrinho', message: 'Oi {nome}, finalize sua compra! {link}',
        start_date: Date.current, end_date: Date.current + 1.year,
        active: '1', send_delay_minutes: 60,
        include_coupon: '1', coupon_code: 'VOLTA10',
        resend_enabled: '1', resend_delay_hours: 24, resend_message: 'Ainda dá tempo, {nome}! {cupom}',
        resend_include_coupon: '1', resend_coupon_code: 'VOLTA15'
      }
    }

    assert_redirected_to automations_path
    campaign = client.campaigns.find_by(kind: 'cart_recovery')
    assert campaign.present?
    assert campaign.active?
    assert_equal 60, campaign.send_delay_minutes
    assert campaign.resend_enabled?
    assert_equal 'VOLTA15', campaign.resend_coupon_code
  end

  test 'cart_recovery_data lists only abandoned checkouts with a phone number' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    with_phone = client.abandoned_checkouts.create!(
      shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999', email: 'a@example.com',
      checkout_created_at: Time.current
    )
    client.abandoned_checkouts.create!(
      shopify_checkout_id: SecureRandom.hex(6), phone: nil, email: 'b@example.com',
      checkout_created_at: Time.current
    )

    get cart_recovery_data_automation_path

    assert_response :success
    assert_match with_phone.email, response.body
  end

  test 'resend_cart_recovery enqueues SendCartRecoveryNotificationJob for an already-notified checkout' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    client.campaigns.create!(
      name: 'Recuperação', kind: 'cart_recovery', message: 'Oi {nome}',
      start_date: Date.current, end_date: Date.current + 1.year, send_delay_minutes: 60
    )
    checkout = client.abandoned_checkouts.create!(
      shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999',
      checkout_created_at: Time.current, first_notified_at: Time.current
    )
    user = build_user(client: client)
    sign_in user

    assert_enqueued_with(job: SendCartRecoveryNotificationJob, args: [checkout.id, 'Oi {nome}', nil, 'first']) do
      post resend_cart_recovery_automation_path(checkout, slot: 'first')
    end

    assert_redirected_to cart_recovery_data_automation_path
  end

  def evolution_client
    Client.create!(name: 'Loja Evo', email: "evo-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
  end

  def saved_cart_campaign(client)
    client.campaigns.create!(
      name: 'Recuperação', kind: 'cart_recovery', message: 'Oi',
      start_date: Date.current - 1.day, end_date: Date.current + 1.year, send_delay_minutes: 60
    )
  end

  test 'update_numbers links only numbers of the same client' do
    client = evolution_client
    campaign = saved_cart_campaign(client)
    mine = client.whatsapp_connections.create!(name: 'Meu', state: 'connected')
    other_client = evolution_client
    foreign = other_client.whatsapp_connections.create!(name: 'Alheio', state: 'connected')
    sign_in build_user(client: client)

    patch automation_numbers_path(kind: 'cart-recovery'), params: { connection_ids: [mine.id, foreign.id] }

    assert_redirected_to edit_cart_recovery_automation_path
    assert_equal [mine.id], campaign.reload.whatsapp_connections.pluck(:id)
  end

  test 'update_numbers removes numbers that were unchecked' do
    client = evolution_client
    campaign = saved_cart_campaign(client)
    mine = client.whatsapp_connections.create!(name: 'Meu', state: 'connected')
    Whatsapp::CampaignConnection.create!(campaign: campaign, connection: mine)
    sign_in build_user(client: client)

    patch automation_numbers_path(kind: 'cart-recovery')

    assert_empty campaign.reload.whatsapp_connections
  end

  test 'update_numbers asks to save the automation first when it is not persisted' do
    client = evolution_client
    client.whatsapp_connections.create!(name: 'Meu', state: 'connected')
    sign_in build_user(client: client)

    patch automation_numbers_path(kind: 'tracking'), params: { connection_ids: [client.whatsapp_connections.first.id] }

    assert_redirected_to edit_tracking_automation_path
    assert_equal 'Salve a automação antes de importar números.', flash[:alert]
    assert_equal 0, Whatsapp::CampaignConnection.count
  end

  test 'update_numbers is a no-op for a Z-API client' do
    client = Client.create!(name: 'Loja', email: "z-#{SecureRandom.hex(4)}@example.com")
    saved_cart_campaign(client)
    sign_in build_user(client: client)

    patch automation_numbers_path(kind: 'cart-recovery'), params: { connection_ids: [1] }

    assert_redirected_to edit_cart_recovery_automation_path
    assert_equal 0, Whatsapp::CampaignConnection.count
  end

  test 'cart recovery edit page shows metrics and the numbers partial for evolution clients' do
    client = evolution_client
    saved_cart_campaign(client)
    client.abandoned_checkouts.create!(shopify_checkout_id: 'a', total_price: 150, checkout_created_at: 1.day.ago)
    sign_in build_user(client: client)

    get edit_cart_recovery_automation_path

    assert_response :success
    assert_includes response.body, 'Ticket médio'
    assert_includes response.body, 'R$ 150,00'
    assert_includes response.body, 'Importe um número responsável'
    assert_includes response.body, 'Nenhum número Evolution conectado'
  end

  test 'cart recovery data page shows metrics and honors period' do
    client = Client.create!(name: 'Loja', email: "m-#{SecureRandom.hex(4)}@example.com")
    client.abandoned_checkouts.create!(shopify_checkout_id: 'a', total_price: 100, checkout_created_at: 2.days.ago)
    client.abandoned_checkouts.create!(shopify_checkout_id: 'b', total_price: 300, checkout_created_at: 20.days.ago)
    sign_in build_user(client: client)

    get cart_recovery_data_automation_path(period: 7)
    assert_includes response.body, 'Ticket médio'
    assert_includes response.body, 'R$ 100,00'

    get cart_recovery_data_automation_path(period: 'bogus')
    assert_includes response.body, 'R$ 200,00'
  end

  test 'zapi client without configuration sees the Zapi warning, not the numbers partial' do
    client = Client.create!(name: 'Loja', email: "w-#{SecureRandom.hex(4)}@example.com")
    sign_in build_user(client: client)

    get edit_cashback_automation_path

    assert_includes response.body, 'Integração Zapi não configurada'
    assert_not_includes response.body, 'Importe um número responsável'
  end

  test 'status row shows Evolution connection instead of Zapi for evolution clients' do
    client = evolution_client
    saved_cart_campaign(client)
    client.whatsapp_connections.create!(name: 'Meu', state: 'connected')
    sign_in build_user(client: client)

    get edit_cart_recovery_automation_path

    assert_not_includes response.body, 'Integração Zapi'
    assert_includes response.body, 'WhatsApp (Evolution)'
    assert_includes response.body, 'Conectado'
  end

  test 'numbers partial asks to save the automation first when not persisted' do
    client = evolution_client
    client.whatsapp_connections.create!(name: 'Meu', state: 'connected')
    sign_in build_user(client: client)

    get edit_tracking_automation_path

    assert_includes response.body, 'Salve a automação antes de importar números.'
    assert_not_includes response.body, 'Salvar números'
  end
end
