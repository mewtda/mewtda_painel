require 'test_helper'

class WhatsappTemplateTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_cloud_phone_number_id: '111', whatsapp_cloud_business_account_id: '222',
                             whatsapp_cloud_access_token: 'tok')
  end

  def build(**attrs)
    @client.whatsapp_templates.new({ label: 'Black Friday 1', body: 'Oi {{1}}, a Black chegou!',
                                     body_example: 'Maria' }.merge(attrs))
  end

  test 'generates the Meta name from the label and avoids collisions' do
    first = build.tap(&:save!)
    second = build.tap(&:save!)
    assert_equal 'black_friday_1', first.name
    assert_equal 'black_friday_1_2', second.name
    assert_equal 'draft', first.status
  end

  test 'meta_payload with variable, footer and button' do
    template = build(footer: 'Responda SAIR para não receber', button_text: 'Ver ofertas',
                     button_url: 'https://loja.com/black').tap(&:save!)
    assert_equal({ name: 'black_friday_1', category: 'MARKETING', language: 'pt_BR',
                   components: [{ type: 'BODY', text: 'Oi {{1}}, a Black chegou!', example: { body_text: [['Maria']] } },
                                { type: 'FOOTER', text: 'Responda SAIR para não receber' },
                                { type: 'BUTTONS', buttons: [{ type: 'URL', text: 'Ver ofertas', url: 'https://loja.com/black' }] }] },
                 template.meta_payload)
  end

  test 'body without variable has no example' do
    template = build(body: 'A Black chegou!', body_example: nil)
    assert template.valid?
    assert_equal [{ type: 'BODY', text: 'A Black chegou!' }], template.meta_payload[:components]
  end

  test 'only {{1}} is allowed and needs an example' do
    refute build(body: 'Oi {{1}} e {{2}}').valid?
    refute build(body_example: '').valid?
    refute build(button_text: 'Ver', button_url: 'loja.com').valid?
  end

  test 'preview_body replaces the variable' do
    assert_equal 'Oi Ana, a Black chegou!', build.preview_body('Ana')
  end

  test 'submit! stores pending and meta id' do
    template = build.tap(&:save!)
    api = Minitest::Mock.new
    api.expect(:create_template, { 'id' => '987', 'status' => 'PENDING' }, [template.meta_payload])
    Whatsapp::Cloud::Api.stub(:new, api) { assert template.submit! }
    api.verify
    template.reload
    assert_equal 'pending', template.status
    assert_equal '987', template.meta_id
    assert template.synced_at
    refute template.editable?
  end

  test 'submit! keeps the Meta error' do
    template = build.tap(&:save!)
    api = Object.new
    def api.create_template(_) = raise(Whatsapp::Cloud::Api::Error, 'Nome já existe')
    Whatsapp::Cloud::Api.stub(:new, api) { refute template.submit! }
    assert_includes template.errors[:base], 'Nome já existe'
    assert_equal 'draft', template.reload.status
  end
end
