require 'test_helper'

class ClientsControllerTest < ActionDispatch::IntegrationTest
  def build_admin
    # No profiles.yml fixture exists, so the admin profile (id 1, referenced by
    # User#admin? via profile_id == 1) must be created here to satisfy the
    # users.profile_id foreign key constraint.
    admin_profile = Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }

    User.create!(
      name: 'Admin', email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123', profile_id: admin_profile.id
    )
  end

  test 'admin can set Meta/Google Ads fields' do
    admin = build_admin
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in admin

    patch client_path(client), params: {
      client: {
        name: client.name,
        email: client.email,
        meta_access_token: 'token123',
        meta_ad_account_id: 'act_1',
        google_ads_customer_id: '1234567890'
      }
    }

    client.reload
    assert_equal 'token123', client.meta_access_token
    assert_equal 'act_1', client.meta_ad_account_id
    assert_equal '1234567890', client.google_ads_customer_id
  end

  test 'admin still sees the active toggle when editing a client' do
    admin = build_admin
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in admin

    get edit_client_path(client)

    assert_response :success
    assert_match 'Cliente ativo', response.body
  end

  test 'submitting a blank meta_access_token preserves the existing stored token' do
    admin = build_admin
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      meta_access_token: 'existing-token', meta_ad_account_id: 'act_1'
    )
    sign_in admin

    patch client_path(client), params: {
      client: { name: client.name, email: client.email, meta_access_token: '' }
    }

    assert_equal 'existing-token', client.reload.meta_access_token
  end

  test 'blank WhatsApp Cloud token preserves the stored one' do
    admin = build_admin
    client = Client.create!(
      name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
      whatsapp_cloud_access_token: 'cloud-token'
    )
    sign_in admin

    patch client_path(client), params: {
      client: { name: client.name, email: client.email, whatsapp_cloud_access_token: '' }
    }

    client.reload
    assert_equal 'cloud-token', client.whatsapp_cloud_access_token
  end

  test 'admin can set the WhatsApp Cloud API credentials' do
    admin = build_admin
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in admin

    patch client_path(client), params: {
      client: { name: client.name, email: client.email, whatsapp_cloud_phone_number_id: '1065',
                whatsapp_cloud_business_account_id: '1022', whatsapp_cloud_access_token: 'EAAG-token' }
    }

    client.reload
    assert client.whatsapp_cloud_configured?
    assert_equal '1022', client.whatsapp_cloud_business_account_id
    assert_equal 'EAAG-token', client.whatsapp_cloud_access_token
  end

  test 'edit page splits integrations into tabs' do
    admin = build_admin
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in admin

    get edit_client_path(client)

    assert_response :success
    %w[geral shopify whatsapp meta google].each do |tab|
      assert_select "[data-tab='#{tab}']"
      assert_select "[data-panel='#{tab}']"
    end
    assert_match 'API Oficial do WhatsApp', response.body
  end
end
