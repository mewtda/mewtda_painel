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

  test 'preview_body replaces the variable' do
    assert_equal 'Oi Ana, a Black chegou!', build.preview_body('Ana')
  end

  test 'sendable means approved and supported by the sender' do
    ok = build(status: 'approved').tap(&:save!)
    build(label: 'Com imagem', status: 'approved', unsupported_reason: 'Cabeçalho com imagem').save!
    build(label: 'Em análise', status: 'pending').save!
    assert_equal [ok.id], @client.whatsapp_templates.sendable.pluck(:id)
  end

  test 'read rate is read over delivered' do
    assert_nil build.read_rate
    assert_equal 25, build(stats_delivered: 8, stats_read: 2).read_rate
  end
end
