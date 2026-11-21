require 'test_helper'

class WhatsappTemplatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    @client = build_client
    sign_in build_user(client: @client)
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                   whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                   whatsapp_cloud_access_token: 'tok')
  end

  def build_user(client:)
    User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                 password_confirmation: 'password123', profile_id: Profile::USER, client:)
  end

  def template(client = @client, **attrs)
    client.whatsapp_templates.create!({ label: 'Black 1', body: 'Oi {{1}}!', status: 'approved', meta_id: '5',
                                        synced_at: Time.current }.merge(attrs))
  end

  def fake_api(templates: [], analytics: {}, analytics_error: nil, on_enable: nil)
    api = Object.new
    api.define_singleton_method(:configured?) { true }
    api.define_singleton_method(:templates) { templates }
    api.define_singleton_method(:template_analytics) do |*, **|
      raise Whatsapp::Cloud::Api::Error, analytics_error if analytics_error

      analytics
    end
    api.define_singleton_method(:enable_template_insights!) { on_enable&.call || true }
    api
  end

  test 'index lists only the current client templates with the Meta numbers' do
    template(stats_sent: 1200, stats_delivered: 1000, stats_read: 400, stats_clicked: 37)
    template(build_client, label: 'De outro cliente')
    get whatsapp_templates_path
    assert_response :success
    assert_match 'Black 1', response.body
    assert_match '1.200', response.body
    assert_match '40% das entregues', response.body
    assert_no_match 'De outro cliente', response.body
    assert_match 'Criar no Gerenciador do WhatsApp', response.body
    assert_no_match 'Novo modelo', response.body
  end

  test 'index warns when the official API is not configured' do
    @client.update!(whatsapp_cloud_access_token: nil)
    get whatsapp_templates_path
    assert_match 'API Oficial', response.body
  end

  test 'index pulls templates from Meta when the last sync is old' do
    pending = template(status: 'pending', synced_at: 1.hour.ago)
    api = fake_api(templates: [{ 'name' => 'black_1', 'status' => 'APPROVED', 'id' => '5' },
                               { 'name' => 'novo_da_meta', 'status' => 'APPROVED', 'id' => '6',
                                 'components' => [{ 'type' => 'BODY', 'text' => 'Chegou!' }] }])
    Whatsapp::Cloud::Api.stub(:new, api) { get whatsapp_templates_path }
    assert_equal 'approved', pending.reload.status
    assert_match 'Novo da meta', response.body
  end

  test 'sync imports from Meta and reports new templates' do
    api = fake_api(templates: [{ 'name' => 'promo', 'status' => 'APPROVED', 'id' => '7',
                                 'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}' }] }])
    Whatsapp::Cloud::Api.stub(:new, api) { post sync_whatsapp_templates_path }
    assert_redirected_to whatsapp_templates_path
    assert_equal '1 modelo novo importado', flash[:notice][/1 modelo novo importado/]
    assert @client.whatsapp_templates.find_by!(name: 'promo').imported?
  end

  test 'when Meta does not return the numbers the page offers to turn on insights' do
    template(synced_at: 1.hour.ago)
    api = fake_api(templates: [{ 'name' => 'black_1', 'status' => 'APPROVED', 'id' => '5' }],
                   analytics_error: 'Template analytics is not enabled')
    Whatsapp::Cloud::Api.stub(:new, api) { get whatsapp_templates_path }
    assert_match 'Ativar insights de modelos na Meta', response.body
    assert_match 'Template analytics is not enabled', response.body
  end

  test 'enable_insights turns on insights in the Meta account' do
    called = false
    api = fake_api(on_enable: -> { called = true })
    Whatsapp::Cloud::Api.stub(:new, api) { post enable_insights_whatsapp_templates_path }
    assert called
    assert_redirected_to whatsapp_templates_path
  end

  test 'templates can no longer be created or edited in the panel' do
    assert_raises(NameError) { new_whatsapp_template_path }
    assert_raises(NameError) { edit_whatsapp_template_path(1) }
  end
end
