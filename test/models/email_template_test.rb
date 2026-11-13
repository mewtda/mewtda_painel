require 'test_helper'

class EmailTemplateTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def valid_attributes(overrides = {})
    {
      client: build_client,
      name: 'Boas-vindas padrão',
      subject: 'Seja bem-vindo(a)!',
      blocks: [{ 'type' => 'heading', 'text' => 'Bem-vindo(a)!' }, { 'type' => 'button', 'text' => 'Ver produtos' }]
    }.merge(overrides)
  end

  test 'valid with required fields and defaults' do
    template = EmailTemplate.new(valid_attributes)
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'requires name, subject and at least one block' do
    template = EmailTemplate.new(client: build_client)

    assert_not template.valid?
    assert_includes template.errors.attribute_names, :name
    assert_includes template.errors.attribute_names, :subject
    assert_includes template.errors[:base], 'Adicione pelo menos um bloco ao e-mail.'
  end

  test 'blocks are sanitized: unknown types, unsafe links and invalid colors are dropped' do
    template = EmailTemplate.new(valid_attributes(blocks_json: [
      { type: 'script', text: 'x' },
      { type: 'button', text: 'Comprar', link: 'javascript:alert(1)', color: 'red', align: 'sideways', extra: 'nope' },
      { type: 'image', link: 'https://loja.com/p', width: '75' }
    ].to_json))

    assert_equal %w[button image], template.blocks.map { |b| b['type'] }
    button = template.blocks.first
    assert_equal '', button['link']
    assert_equal '', button['color']
    assert_equal 'center', button['align']
    assert_not button.key?('extra')
    assert button['id'].present?
    assert_equal 'https://loja.com/p', template.blocks.last['link']
    assert_equal '75', template.blocks.last['width']
  end

  test 'invalid blocks JSON results in no blocks' do
    template = EmailTemplate.new(valid_attributes(blocks_json: '{not json'))
    assert_equal [], template.blocks
    assert_not template.valid?
  end

  test 'design falls back to defaults for unknown values' do
    template = EmailTemplate.new(valid_attributes(design_json: { font: 'comic', bg: '#000000', preheader: 'Oi' }.to_json))

    assert_equal 'arial', template.design['font']
    assert_equal '#000000', template.design['bg']
    assert_equal 'Oi', template.design['preheader']
    assert_equal '#ffffff', template.design['content_bg']
  end

  test 'legacy templates without blocks are converted from heading/body/layout' do
    template = EmailTemplate.new(valid_attributes(blocks: [], heading: 'Olá', body: 'Texto', button_text: 'Ir',
                                                  button_url: 'https://loja.com', coupon_code: 'X10', layout: 'banner'))

    assert template.valid?, template.errors.full_messages.to_s
    assert_equal %w[logo heading text coupon button], template.content_blocks.map { |b| b['type'] }
    assert_equal 'https://loja.com', template.content_blocks.last['link']
  end

  test 'legacy back in stock templates get a product block' do
    template = EmailTemplate.new(valid_attributes(blocks: [], heading: 'Voltou', body: 'Texto', button_text: 'Comprar',
                                                  trigger_kind: :back_in_stock, layout: 'image_left'))

    assert_equal %w[logo heading text product], template.content_blocks.map { |b| b['type'] }
  end

  test 'defaults to manual trigger_kind and image_top layout' do
    template = EmailTemplate.create!(valid_attributes)
    assert template.manual?
    assert_equal 'image_top', template.layout
  end

  test 'rejects an unknown layout' do
    template = EmailTemplate.new(valid_attributes(layout: 'sideways'))
    assert_not template.valid?
  end

  test 'accepts the image_top_bottom layout' do
    template = EmailTemplate.new(valid_attributes(layout: 'image_top_bottom'))
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'rejects a non-hex accent_color' do
    template = EmailTemplate.new(valid_attributes(accent_color: 'purple'))
    assert_not template.valid?
  end

  test 'cart_recovery requires trigger_delay_hours' do
    template = EmailTemplate.new(valid_attributes(trigger_kind: :cart_recovery))
    assert_not template.valid?
    assert_includes template.errors.attribute_names, :trigger_delay_hours

    template.trigger_delay_hours = 2
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'inactive_customer requires trigger_inactive_days' do
    template = EmailTemplate.new(valid_attributes(trigger_kind: :inactive_customer))
    assert_not template.valid?
    assert_includes template.errors.attribute_names, :trigger_inactive_days

    template.trigger_inactive_days = 30
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'post_purchase requires trigger_days_after_purchase' do
    template = EmailTemplate.new(valid_attributes(trigger_kind: :post_purchase))
    assert_not template.valid?
    assert_includes template.errors.attribute_names, :trigger_days_after_purchase

    template.trigger_days_after_purchase = 3
    assert template.valid?, template.errors.full_messages.to_s
  end

  test 'welcome and cashback need no extra trigger config' do
    assert EmailTemplate.new(valid_attributes(trigger_kind: :welcome)).valid?
    assert EmailTemplate.new(valid_attributes(trigger_kind: :cashback)).valid?
  end

  test 'preset returns prefilled attributes for a known key' do
    preset = EmailTemplate.preset(:cart_recovery)

    assert_equal 'image_text', preset[:blocks].second['type']
    assert_equal 'cart_recovery', preset[:trigger_kind]
    assert_equal 2, preset[:trigger_config]['delay_hours']
    assert preset[:subject].present?
  end

  test 'preset returns nil for an unknown key' do
    assert_nil EmailTemplate.preset(:not_a_real_preset)
  end

  test 'preset returns nil for a blank key' do
    assert_nil EmailTemplate.preset(nil)
    assert_nil EmailTemplate.preset('')
  end

  test 'a client can have many email templates, destroyed with it' do
    client = build_client
    template = EmailTemplate.create!(valid_attributes(client: client))

    client.destroy

    assert_not EmailTemplate.exists?(template.id)
  end

  test 'every preset builds a valid template' do
    EmailTemplate::PRESETS.each do |key, preset|
      template = EmailTemplate.new(preset.merge(client: build_client))
      assert template.valid?, "#{key}: #{template.errors.full_messages}"
      assert_equal preset[:blocks].size, template.blocks.size
    end
  end
end
