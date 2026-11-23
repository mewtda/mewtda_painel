require 'test_helper'

class Whatsapp::Cloud::TemplateSyncTest < ActiveSupport::TestCase
  test 'updates status and rejection reason by name' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                            whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                            whatsapp_cloud_access_token: 't')
    ok = client.whatsapp_templates.create!(label: 'Um', body: 'Oi', status: 'pending')
    bad = client.whatsapp_templates.create!(label: 'Dois', body: 'Oi', status: 'pending')
    api = Object.new
    def api.templates
      [{ 'name' => 'um', 'status' => 'APPROVED', 'id' => '10' },
       { 'name' => 'dois', 'status' => 'REJECTED', 'rejected_reason' => 'PROMOTIONAL', 'id' => '11' }]
    end
    def api.template_analytics(*, **) = {}
    Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }

    assert_equal 'approved', ok.reload.status
    assert_equal '10', ok.meta_id
    assert_equal 'rejected', bad.reload.status
    assert_equal 'PROMOTIONAL', bad.rejection_reason
    assert bad.synced_at
  end

  test 'the sync job also checks approved templates of clients with WhatsApp messages to send' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                            whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                            whatsapp_cloud_access_token: 't')
    template = client.whatsapp_templates.create!(label: 'Um', body: 'Oi', status: 'approved')
    campaign = client.campaigns.create!(status: 'scheduled')
    campaign.messages.create!(channel: 'whatsapp', whatsapp_template: template, status: 'scheduled', next_run_at: 1.day.from_now)
    api = Object.new
    def api.configured? = true
    def api.templates = [{ 'name' => 'um', 'status' => 'PAUSED', 'id' => '10' }]
    def api.template_analytics(*, **) = {}
    Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::TemplateSyncJob.perform_now }
    assert_equal 'paused', template.reload.status
  end

  def connected_client
    Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                   whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                   whatsapp_cloud_access_token: 't')
  end

  def fake_api(templates, analytics: {}, analytics_error: nil)
    api = Object.new
    api.define_singleton_method(:configured?) { true }
    api.define_singleton_method(:templates) { templates }
    api.define_singleton_method(:template_analytics) do |ids, from:, to:|
      raise Whatsapp::Cloud::Api::Error, analytics_error if analytics_error

      @analytics_call = { ids:, inside_90_days: from > 90.days.ago, from_midnight: from == from.beginning_of_day }
      analytics
    end
    api.define_singleton_method(:analytics_call) { @analytics_call }
    api
  end

  test 'imports templates created in the Meta account, marking the ones the panel cannot send' do
    client = connected_client
    api = fake_api([
      { 'name' => 'promo_natal', 'status' => 'APPROVED', 'id' => '50', 'category' => 'MARKETING', 'language' => 'pt_BR',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Oi {{1}}, chegou o Natal!', 'example' => { 'body_text' => [['Ana']] } },
          { 'type' => 'FOOTER', 'text' => 'Responda SAIR' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Ver loja', 'url' => 'https://loja.com/' }] }
        ] },
      { 'name' => 'com_imagem', 'status' => 'APPROVED', 'id' => '51', 'category' => 'MARKETING', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Olha' }] },
      { 'name' => 'dois_campos', 'status' => 'PENDING', 'id' => '52', 'category' => 'MARKETING', 'language' => 'pt_BR',
        'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu cupom é {{2}}' }] }
    ])

    result = Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }

    assert_equal 3, result.imported
    natal = client.whatsapp_templates.find_by!(name: 'promo_natal')
    assert natal.imported?
    assert_equal ['approved', '50', 'Oi {{1}}, chegou o Natal!', 'Ana', 'Responda SAIR', 'Ver loja', 'https://loja.com/'],
                 [natal.status, natal.meta_id, natal.body, natal.body_example, natal.footer, natal.button_text, natal.button_url]
    assert natal.supported?
    assert_match 'imagem', client.whatsapp_templates.find_by!(name: 'com_imagem').unsupported_reason
    assert_equal 'pending', client.whatsapp_templates.find_by!(name: 'dois_campos').status
    assert_match '{{1}}', client.whatsapp_templates.find_by!(name: 'dois_campos').unsupported_reason
    assert_equal %w[promo_natal], client.whatsapp_templates.sendable.pluck(:name)

    # Rodar de novo não duplica.
    again = Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }
    assert_equal 0, again.imported
    assert_equal 3, client.whatsapp_templates.count
  end

  test 'pulls sent, delivered, read and clicks from the Meta template analytics' do
    client = connected_client
    template = client.whatsapp_templates.create!(label: 'Um', body: 'Oi', status: 'approved', meta_id: '10')
    api = fake_api([{ 'name' => 'um', 'status' => 'APPROVED', 'id' => '10' }],
                   analytics: { '10' => { sent: 40, delivered: 38, read: 19, clicked: 4 } })

    result = Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }

    assert_nil result.stats_error
    assert_equal({ ids: ['10'], inside_90_days: true, from_midnight: true }, api.analytics_call)
    template.reload
    assert_equal [40, 38, 19, 4], [template.stats_sent, template.stats_delivered, template.stats_read, template.stats_clicked]
    assert_equal 50, template.read_rate
    assert template.stats_synced_at
  end

  test 'the analytics window starts at a UTC midnight inside the last 90 UTC days, even late at night in Brasilia' do
    client = connected_client
    client.whatsapp_templates.create!(label: 'Um', body: 'Oi', status: 'approved', meta_id: '10')
    api = fake_api([{ 'name' => 'um', 'status' => 'APPROVED', 'id' => '10' }])
    api.define_singleton_method(:template_analytics) do |_ids, from:, to:| # rubocop:disable Lint/UnusedBlockArgument
      @from = from
      {}
    end
    api.define_singleton_method(:analytics_from) { @from }

    # 22/11 às 23h em Brasília já é 23/11 em UTC.
    travel_to Time.utc(2026, 11, 23, 2, 0) do
      Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }
    end

    assert_equal Time.utc(2026, 8, 26), api.analytics_from.utc
  end

  test 'an analytics error from Meta is returned without breaking the template sync' do
    client = connected_client
    template = client.whatsapp_templates.create!(label: 'Um', body: 'Oi', status: 'pending', meta_id: '10')
    api = fake_api([{ 'name' => 'um', 'status' => 'APPROVED', 'id' => '10' }], analytics_error: 'Insights desligados')

    result = Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }

    assert_equal 'Insights desligados', result.stats_error
    assert_equal 'approved', template.reload.status
  end

  test 'a template deleted in the Meta account is disabled in the panel' do
    client = connected_client
    gone = client.whatsapp_templates.create!(label: 'Velho', body: 'Oi', status: 'approved', meta_id: '9')
    api = fake_api([])

    Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }

    assert_equal ['disabled', 'Excluído na Meta'], [gone.reload.status, gone.rejection_reason]
    assert_empty client.whatsapp_templates.sendable
  end
end
