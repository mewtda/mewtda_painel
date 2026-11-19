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
    client.whatsapp_templates.create!({ label: 'Black 1', body: 'Oi {{1}}!', body_example: 'Maria' }.merge(attrs))
  end

  test 'index lists only the current client templates' do
    template
    template(build_client, label: 'De outro cliente')
    get whatsapp_templates_path
    assert_response :success
    assert_match 'Black 1', response.body
    assert_no_match 'De outro cliente', response.body
  end

  test 'index warns when the official API is not configured' do
    @client.update!(whatsapp_cloud_access_token: nil)
    get whatsapp_templates_path
    assert_match 'API Oficial', response.body
  end

  test 'index refreshes pending templates from Meta' do
    pending = template(status: 'pending')
    api = Object.new
    def api.configured? = true
    def api.templates = [{ 'name' => 'black_1', 'status' => 'APPROVED', 'id' => '5' }]
    Whatsapp::Cloud::Api.stub(:new, api) { get whatsapp_templates_path }
    assert_equal 'approved', pending.reload.status
  end

  test 'create saves a draft and redirects' do
    assert_difference -> { @client.whatsapp_templates.count } do
      post whatsapp_templates_path, params: { whatsapp_template: { label: 'Nova', body: 'Oi {{1}}', body_example: 'Ana' } }
    end
    assert_redirected_to whatsapp_templates_path
    assert_equal 'draft', @client.whatsapp_templates.last.status
  end

  test 'create with errors re-renders the form' do
    post whatsapp_templates_path, params: { whatsapp_template: { label: '', body: '' } }
    assert_response :unprocessable_entity
  end

  test 'approved templates cannot be edited' do
    approved = template(status: 'approved')
    patch whatsapp_template_path(approved), params: { whatsapp_template: { body: 'Outro texto' } }
    assert_redirected_to whatsapp_templates_path
    assert_equal 'Oi {{1}}!', approved.reload.body
  end

  test 'submit sends to Meta and marks pending' do
    draft = template
    api = Object.new
    def api.create_template(_) = { 'id' => '77', 'status' => 'PENDING' }
    Whatsapp::Cloud::Api.stub(:new, api) { post submit_whatsapp_template_path(draft) }
    assert_redirected_to whatsapp_templates_path
    assert_equal 'pending', draft.reload.status
  end

  test 'duplicate creates a draft copy' do
    approved = template(status: 'approved', meta_id: '9')
    post duplicate_whatsapp_template_path(approved)
    copy = @client.whatsapp_templates.order(:id).last
    assert_equal 'Black 1 (cópia)', copy.label
    assert_equal 'draft', copy.status
    assert_nil copy.meta_id
    assert_redirected_to edit_whatsapp_template_path(copy)
  end

  test 'destroy deletes on Meta when submitted' do
    sent = template(status: 'rejected', meta_id: '9')
    deleted = []
    api = Object.new
    def api.configured? = true
    api.define_singleton_method(:delete_template) { |name:| deleted << name }
    Whatsapp::Cloud::Api.stub(:new, api) { delete whatsapp_template_path(sent) }
    assert_equal ['black_1'], deleted
    refute WhatsappTemplate.exists?(sent.id)
  end

  test 'another client template is not reachable' do
    other = template(build_client, label: 'Alheio')
    get edit_whatsapp_template_path(other)
    assert_redirected_to whatsapp_templates_path
  end
end
