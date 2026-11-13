require 'test_helper'

class AutomationActionsControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  def build_automation(client, name: 'Rastreio')
    client.automations.create!(
      name: name, kind: 'shipping_tracking', message: 'Oi {nome}',
      start_date: Date.current, end_date: Date.current + 1.year, max_sends: 3, interval_days: 4
    )
  end

  def build_client
    Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'redirects when the admin has no client selected' do
    sign_in build_user(admin: true)

    get automation_actions_path('rastreio')

    assert_redirected_to crm_path
  end

  test 'old campaign urls redirect to the automations screens' do
    get '/crm/campaigns'
    assert_redirected_to '/crm/automations'

    get '/crm/campaigns/rastreio-de-pedidos'
    assert_redirected_to '/crm/automations/rastreio-de-pedidos/actions'
  end

  test 'index allows an admin via the selected client in session (used by "Ver Dados")' do
    client = build_client
    automation = build_automation(client)
    sign_in build_user(admin: true)

    post update_selected_client_path, params: { client_id: client.id }
    get automation_actions_path(automation)

    assert_response :success
  end

  test 'index allows a non-admin client user' do
    client = build_client
    automation = build_automation(client)
    sign_in build_user(client: client)

    get automation_actions_path(automation)

    assert_response :success
  end

  test 'index does not open an automation from another store' do
    automation = build_automation(build_client)
    sign_in build_user(client: build_client)

    get automation_actions_path(automation)

    assert_redirected_to automations_path
  end

  test 'resend enqueues SendAutomationNotificationJob for the given notification' do
    client = build_client
    sign_in build_user(client: client)
    automation = build_automation(client)
    customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6), name: 'Cliente Teste')
    automation_action = automation.automation_actions.create!(customer: customer, kind: 'shipping_tracking', status: 'sent')

    assert_enqueued_with(job: SendAutomationNotificationJob, args: [automation_action.id]) do
      post resend_automation_action_path(automation_id: automation.to_param, id: automation_action.to_param)
    end

    assert_redirected_to automation_actions_path(automation)
  end

  test 'the automation url uses a friendly slug instead of the numeric id' do
    client = build_client
    automation = build_automation(client, name: 'Rastreio de Pedidos')

    assert_equal 'rastreio-de-pedidos', automation.slug
    assert_includes automation_actions_path(automation), 'rastreio-de-pedidos'
    assert_not_includes automation_actions_path(automation), automation.id.to_s

    sign_in build_user(client: client)
    get automation_actions_path(automation.slug)

    assert_response :success
  end
end
