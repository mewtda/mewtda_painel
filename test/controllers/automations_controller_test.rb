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

  test 'edit_tracking initializes a not-yet-persisted automation with tracking defaults' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_tracking_automation_path

    assert_response :success
    assert_equal 0, client.automations.count
  end

  test 'update_tracking creates the shipping_tracking automation' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch tracking_automation_path, params: {
      automation: {
        name: 'Rastreio', message: 'Seu pedido {pedido} saiu, rastreio: {rastreio}',
        start_date: Date.current, end_date: Date.current + 1.year,
        active: '1', max_sends: 3, interval_days: 4
      }
    }

    assert_redirected_to automations_path
    automation = client.automations.find_by(kind: 'shipping_tracking')
    assert automation.present?
    assert automation.active?
  end

  test 'edit_cashback initializes a not-yet-persisted automation with cashback defaults' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_cashback_automation_path

    assert_response :success
    assert_equal 0, client.automations.count
  end

  test 'update_cashback creates the cashback automation' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    patch cashback_automation_path, params: {
      automation: {
        name: 'Cashback', message: 'Oi {nome}, use {cupom}!',
        start_date: Date.current, end_date: Date.current + 1.year,
        active: '1', days_after_purchase: 7
      }
    }

    assert_redirected_to automations_path
    automation = client.automations.find_by(kind: 'cashback')
    assert automation.present?
    assert automation.active?
    assert_equal 7, automation.days_after_purchase
  end

  test 'edit_cart_recovery initializes a not-yet-persisted automation with defaults' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get edit_cart_recovery_automation_path

    assert_response :success
    assert_equal 0, client.automations.count
  end

  test 'update_cart_recovery creates the cart_recovery automation with the approved template' do
    client = cloud_client
    template = client.whatsapp_templates.create!(label: 'Carrinho', body: 'Ei, {{1}}!', status: 'approved')
    sign_in build_user(client: client)

    patch cart_recovery_automation_path, params: {
      automation: {
        name: 'Recuperação de Carrinho', whatsapp_template_id: template.id,
        start_date: Date.current, end_date: Date.current + 1.year,
        active: '1', send_delay_minutes: 5,
        include_coupon: '1', coupon_code: 'VOLTA10'
      },
      tab: 'mensagens'
    }

    assert_redirected_to edit_cart_recovery_automation_path(anchor: 'mensagens')
    automation = client.automations.find_by(kind: 'cart_recovery')
    assert automation.active?
    assert_equal 5, automation.send_delay_minutes
    assert_equal template, automation.whatsapp_template
    assert_equal 'VOLTA10', automation.coupon_code
  end

  def cloud_client
    Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                   whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                   whatsapp_cloud_access_token: 't')
  end

  test 'loja com API Oficial: mensagens mostram só modelos aprovados da Meta' do
    client = cloud_client
    client.whatsapp_templates.create!(label: 'Carrinho aprovado', body: 'Ei, {{1}}!', status: 'approved')
    client.whatsapp_templates.create!(label: 'Carrinho em análise', body: 'Oi', status: 'pending')
    sign_in build_user(client: client)

    get edit_cart_recovery_automation_path

    assert_response :success
    assert_includes response.body, 'Carrinho aprovado'
    assert_not_includes response.body, 'Carrinho em análise'
    assert_not_includes response.body, 'automation[message]'
    assert_not_includes response.body, 'Segunda mensagem'
  end

  test 'loja com API Oficial: salva desligada sem modelo, com início hoje e sem data final' do
    client = cloud_client
    sign_in build_user(client: client)

    patch cart_recovery_automation_path, params: {
      automation: { name: 'Recuperação', start_date: Date.current, no_end_date: '1', active: '0',
                    send_delay_minutes: 60, include_coupon: '1', coupon_code: 'FARAH' }
    }

    automation = client.automations.find_by(kind: 'cart_recovery')
    assert automation.present?
    assert_not automation.active?
    assert_nil automation.end_date
    assert_equal Date.current, automation.start_date
  end

  test 'loja com API Oficial: não ativa sem modelo aprovado da Meta' do
    client = cloud_client
    sign_in build_user(client: client)

    patch cart_recovery_automation_path, params: {
      automation: { name: 'Recuperação', start_date: Date.current, no_end_date: '1', active: '1',
                    send_delay_minutes: 60, message: 'texto livre' }
    }

    assert_response :unprocessable_entity
    assert_equal 0, client.automations.count
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

  def saved_cart_automation(client, template: nil)
    client.automations.create!(
      name: 'Recuperação', kind: 'cart_recovery', whatsapp_template: template, active: template.present?,
      start_date: Date.current - 1.day, end_date: Date.current + 1.year, send_delay_minutes: 60
    )
  end

  def notified_checkout(client)
    client.abandoned_checkouts.create!(
      shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999',
      checkout_created_at: Time.current, first_notified_at: Time.current, whatsapp_provider: 'cloud'
    )
  end

  test 'resend_cart_recovery reenvia o modelo aprovado para um checkout já avisado' do
    client = cloud_client
    template = client.whatsapp_templates.create!(label: 'Carrinho', body: 'Ei, {{1}}!', status: 'approved')
    saved_cart_automation(client, template:)
    checkout = notified_checkout(client)
    sign_in build_user(client: client)

    assert_enqueued_with(job: SendCartRecoveryTemplateJob, args: [checkout.id, true]) do
      post resend_cart_recovery_automation_path(checkout)
    end
    assert_redirected_to cart_recovery_data_automation_path
    assert_equal 'Reenvio agendado com sucesso.', flash[:notice]
  end

  test 'resend_cart_recovery avisa quando não há modelo aprovado' do
    client = cloud_client
    saved_cart_automation(client)
    checkout = notified_checkout(client)
    sign_in build_user(client: client)

    assert_no_enqueued_jobs only: SendCartRecoveryTemplateJob do
      post resend_cart_recovery_automation_path(checkout)
    end
    assert_redirected_to cart_recovery_data_automation_path
    assert_match 'modelo aprovado', flash[:alert]
  end

  test 'cart recovery edit page shows metrics and warns when the official API is missing' do
    client = Client.create!(name: 'Loja', email: "m-#{SecureRandom.hex(4)}@example.com")
    saved_cart_automation(client)
    client.abandoned_checkouts.create!(shopify_checkout_id: 'a', total_price: 150, checkout_created_at: 1.day.ago)
    sign_in build_user(client: client)

    get edit_cart_recovery_automation_path

    assert_response :success
    assert_includes response.body, 'Ticket médio'
    assert_includes response.body, 'R$ 150,00'
    assert_includes response.body, 'API Oficial do WhatsApp não configurada'
    assert_not_includes response.body, 'Evolution'
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

  test 'a fila mostra só checkouts a partir do início da automação' do
    client = cloud_client
    saved_cart_automation(client).update_columns(start_date: Date.current)
    client.abandoned_checkouts.create!(shopify_checkout_id: 'old', phone: '+5511999999998', email: 'antigo@example.com',
                                       checkout_created_at: 3.days.ago)
    client.abandoned_checkouts.create!(shopify_checkout_id: 'new', phone: '+5511999999999', email: 'hoje@example.com',
                                       checkout_created_at: Time.current)
    sign_in build_user(client: client)

    get cart_recovery_data_automation_path

    assert_includes response.body, 'hoje@example.com'
    assert_not_includes response.body, 'antigo@example.com'
    assert_includes response.body, '1 registros'
  end

  test 'cashback e rastreio aparecem como desativados' do
    client = cloud_client
    sign_in build_user(client: client)

    get edit_cashback_automation_path
    assert_includes response.body, 'Envio por WhatsApp desativado'

    get edit_tracking_automation_path
    assert_includes response.body, 'Envio por WhatsApp desativado'

    get automations_path
    assert_includes response.body, 'Desativada por enquanto'
  end

  test 'status row shows the official API and the chosen template' do
    client = cloud_client
    template = client.whatsapp_templates.create!(label: 'Carrinho FARAH', body: 'Ei, {{1}}!', status: 'approved')
    saved_cart_automation(client, template:)
    sign_in build_user(client: client)

    get edit_cart_recovery_automation_path

    assert_includes response.body, 'API Oficial configurada'
    assert_includes response.body, 'Carrinho FARAH'
  end

  test 'cart recovery page uses tabs without numbers or conversations' do
    client = cloud_client
    saved_cart_automation(client)
    sign_in build_user(client: client)

    get edit_cart_recovery_automation_path

    assert_response :success
    %w[geral mensagens resultados].each do |tab|
      assert_select '.scr-tab[data-tab=?]', tab
      assert_select '.scr-panel[data-panel=?]', tab
    end
    %w[numeros conversas].each { |tab| assert_select '.scr-tab[data-tab=?]', tab, count: 0 }
    assert_select '.scr-switch input[type=checkbox][name=?]', 'automation[active]'
  end
end
