require 'test_helper'

class CampaignsControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, client: nil)
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client
    )
  end

  test 'redirects when the admin has no client selected' do
    admin = build_user(admin: true)
    sign_in admin

    get campaigns_path

    assert_redirected_to crm_path
  end

  test 'index is deactivated and redirects to automations' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    get campaigns_path

    assert_redirected_to automations_path
  end

  test 'show still allows an admin via the selected client in session (used by "Ver Dados")' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    campaign = client.campaigns.create!(
      name: 'Rastreio', kind: 'shipping_tracking', message: 'Oi {nome}',
      start_date: Date.current, end_date: Date.current + 1.year, max_sends: 3, interval_days: 4
    )
    admin = build_user(admin: true)
    sign_in admin

    post update_selected_client_path, params: { client_id: client.id }
    get campaign_path(campaign)

    assert_response :success
  end

  test 'show still allows a non-admin client user' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    campaign = client.campaigns.create!(
      name: 'Rastreio', kind: 'shipping_tracking', message: 'Oi {nome}',
      start_date: Date.current, end_date: Date.current + 1.year, max_sends: 3, interval_days: 4
    )
    user = build_user(client: client)
    sign_in user

    get campaign_path(campaign)

    assert_response :success
  end

  test 'resend_action enqueues SendCampaignNotificationJob for the given notification' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)
    sign_in user

    campaign = client.campaigns.create!(
      name: 'Rastreio', kind: 'shipping_tracking', message: 'Oi {nome}',
      start_date: Date.current, end_date: Date.current + 1.year, max_sends: 3, interval_days: 4
    )
    customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6), name: 'Cliente Teste')
    campaign_action = campaign.campaign_actions.create!(customer: customer, kind: 'shipping_tracking', status: 'sent')

    assert_enqueued_with(job: SendCampaignNotificationJob, args: [campaign_action.id]) do
      post resend_campaign_action_path(campaign_id: campaign.to_param, action_id: campaign_action.to_param)
    end

    assert_redirected_to campaign_path(campaign)
  end

  test 'campaign_path uses a friendly slug instead of the numeric id' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    campaign = client.campaigns.create!(
      name: 'Rastreio de Pedidos', kind: 'shipping_tracking', message: 'Oi {nome}',
      start_date: Date.current, end_date: Date.current + 1.year, max_sends: 3, interval_days: 4
    )

    assert_equal 'rastreio-de-pedidos', campaign.slug
    assert_includes campaign_path(campaign), 'rastreio-de-pedidos'
    assert_not_includes campaign_path(campaign), campaign.id.to_s

    user = build_user(client: client)
    sign_in user
    get campaign_path(campaign.slug)

    assert_response :success
  end
end
