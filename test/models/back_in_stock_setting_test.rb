require 'test_helper'

class BackInStockSettingTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_template(client, **attrs)
    EmailTemplate.create!(client:, name: 'Aviso', subject: 'Voltou!', blocks: [{ 'type' => 'heading', 'text' => 'Oi' }], **attrs)
  end

  test 'uses the chosen template' do
    client = build_client
    chosen = build_template(client, name: 'Escolhido')

    assert_equal chosen, client.create_back_in_stock_setting!(email_template: chosen).email_template
  end

  test 'has no template until one is chosen' do
    client = build_client
    build_template(client, name: 'Outro', trigger_kind: 'back_in_stock', active: true)

    assert_nil client.create_back_in_stock_setting!.email_template
  end

  test 'rejects a template from another store' do
    other = build_template(build_client, name: 'De outra loja')
    setting = build_client.build_back_in_stock_setting(email_template_id: other.id)

    assert_not setting.valid?
    assert_includes setting.errors.attribute_names, :email_template_id
  end
end
