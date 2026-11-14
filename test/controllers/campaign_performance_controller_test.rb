require 'test_helper'

class CampaignPerformanceControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    sign_in User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
  end

  def campaign(client: @client, started_at: 2.days.ago, **attrs)
    client.campaigns.create!({ name: 'Black Friday', status: 'sent', started_at:, recipients_count: 10, sent_count: 8,
                               blocked_count: 1, failed_count: 1 }.merge(attrs))
  end

  test 'shows the reach numbers of campaigns started in the period' do
    campaign

    get campaign_performance_path

    assert_response :success
    assert_match 'Desempenho das campanhas', response.body
    assert_match 'Faturamento gerado', response.body
    assert_match '80,00%', response.body
  end

  test 'offers the channel filter and keeps the chosen channel' do
    campaign

    get campaign_performance_path(canal: 'email')

    assert_response :success
    assert_select 'select[name=canal] option[selected]', text: 'E-mail'
  end

  test 'shows delivery and engagement cards once there are tracked events' do
    sent = campaign
    recipient = sent.recipients.create!(email: 'ana@example.com', status: 'sent', sent_at: Time.current)
    %w[delivery open].each do |type|
      EmailEvent.create!(client: @client, source: 'campaign', campaign: sent, campaign_recipient: recipient, event_type: type,
                         ses_message_id: 'm-1', occurred_at: Time.current)
    end

    get campaign_performance_path

    assert_match 'Entrega e engajamento', response.body
    assert_match 'Taxa de abertura', response.body
    assert_match 'Melhores horários', response.body
  end

  test 'explains that tracking is pending when there are no events' do
    campaign

    get campaign_performance_path

    assert_match 'quando o rastreio do envio estiver ligado', response.body
    assert_no_match 'Taxa de abertura', response.body
  end

  test 'campaigns outside the period are left out' do
    campaign(started_at: 90.days.ago)

    get campaign_performance_path(periodo: '7d')

    assert_match 'Nenhuma campanha enviada neste período', response.body
  end

  test 'choosing a campaign ignores the period' do
    old = campaign(started_at: 90.days.ago)

    get campaign_performance_path(periodo: '7d', campanha: old.id)

    assert_no_match 'Nenhuma campanha enviada', response.body
    assert_match 'O período não vale para a campanha escolhida', response.body
  end

  test 'campaigns of other stores never show up' do
    other = Client.create!(name: 'Outra', email: "outra-#{SecureRandom.hex(4)}@example.com")
    foreign = campaign(client: other)

    get campaign_performance_path(campanha: foreign.id)

    assert_match 'Nenhuma campanha enviada', response.body
  end

  test 'the details modal links to the performance of that campaign' do
    sent = campaign

    get details_campaign_path(sent)

    assert_includes response.body, campaign_performance_path(campanha: sent.id)
  end
end
