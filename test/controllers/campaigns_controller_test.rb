require 'test_helper'

class CampaignsControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                 password_confirmation: 'password123', profile_id: Profile::USER, client:)
  end

  def template(client)
    EmailTemplate.create!(client:, name: 'Modelo', subject: 'Oi', blocks: [{ 'type' => 'heading', 'text' => 'Oi' }])
  end

  setup do
    @client = build_client
    sign_in build_user(client: @client)
  end

  test 'index lists only the current store campaigns' do
    @client.campaigns.create!(name: 'Minha campanha')
    build_client.campaigns.create!(name: 'De outra loja')

    get campaigns_path

    assert_response :success
    assert_match 'Minha campanha', response.body
    assert_no_match 'De outra loja', response.body
  end

  test 'index searches campaigns by name' do
    @client.campaigns.create!(name: 'Promoção de verão')
    @client.campaigns.create!(name: 'Dia das mães')

    get campaigns_path(q: 'verão')

    assert_match 'Promoção de verão', response.body
    assert_no_match 'Dia das mães', response.body
  end

  test 'index filters by channel' do
    @client.campaigns.create!(name: 'Por e-mail')

    get campaigns_path(canal: 'email')
    assert_match 'Por e-mail', response.body

    get campaigns_path(canal: 'nenhum')
    assert_match 'Por e-mail', response.body
  end

  test 'create makes a draft and goes to the editor' do
    assert_difference '@client.campaigns.count', 1 do
      post campaigns_path
    end

    campaign = @client.campaigns.last
    assert_redirected_to edit_campaign_path(campaign)
    assert campaign.draft?
  end

  test 'edit renders the steps for a draft' do
    campaign = @client.campaigns.create!

    get edit_campaign_path(campaign)

    assert_response :success
    assert_match 'Quando enviar', response.body
    assert_match 'a cada 1.000 e-mails', response.body
  end

  test 'update autosaves and returns the summary' do
    campaign = @client.campaigns.create!
    segment = @client.segments.create!(name: 'Lista', kind: 'static')

    patch campaign_path(campaign), params: { campaign: { name: 'Verão', segment_id: segment.id, email_template_id: template(@client).id } },
                                         as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal 'Verão', campaign.reload.name
    assert_equal true, body['steps']['audience']
    assert_equal 0, body['audience']['recipients']
    assert_equal [], body['missing']
    assert_equal 'Oi', body['template_subject']
  end

  test 'cost shows less than one cent for a tiny audience instead of zero' do
    segment = @client.segments.create!(name: 'Eu', kind: 'static')
    customer = Customer.create!(first_name: 'Eu', email: 'eu@example.com', shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, email: 'eu@example.com', refreshed_at: Time.current)
    SegmentMembership.create!(segment:, customer:)
    campaign = @client.campaigns.create!(segment:)

    patch campaign_path(campaign), params: { campaign: { name: 'Teste' } }, as: :json

    assert_equal 1, response.parsed_body['audience']['recipients']
    assert_equal 'menos de R$ 0,01', response.parsed_body['audience']['cost']
  end

  test 'update rejects a segment from another store' do
    campaign = @client.campaigns.create!
    foreign = build_client.segments.create!(name: 'Alheio', kind: 'static')

    patch campaign_path(campaign), params: { campaign: { segment_id: foreign.id } }, as: :json

    assert_response :unprocessable_entity
    assert_nil campaign.reload.segment_id
  end

  test 'a campaign that is not a draft cannot be edited' do
    campaign = @client.campaigns.create!(status: 'sent')

    get edit_campaign_path(campaign)
    assert_redirected_to campaigns_path

    patch campaign_path(campaign), params: { campaign: { name: 'Novo' } }, as: :json
    assert_response :unprocessable_entity
  end

  test 'cannot open a campaign from another store' do
    campaign = build_client.campaigns.create!

    get edit_campaign_path(campaign)

    assert_redirected_to campaigns_path
  end

  test 'destroy removes drafts but keeps sent campaigns' do
    draft = @client.campaigns.create!
    sent = @client.campaigns.create!(status: 'sent')

    assert_difference '@client.campaigns.count', -1 do
      delete campaign_path(draft)
    end
    assert_no_difference '@client.campaigns.count' do
      delete campaign_path(sent)
    end
  end

  test 'preview renders the chosen template' do
    campaign = @client.campaigns.create!(email_template: template(@client))

    get preview_campaign_path(campaign)

    assert_response :success
    assert_match 'Oi', response.body
  end

  test 'send_test validates the address, the template and the domain' do
    campaign = @client.campaigns.create!

    post send_test_campaign_path(campaign), params: { test_email: 'ruim' }
    assert_response :unprocessable_entity

    post send_test_campaign_path(campaign), params: { test_email: 'ana@example.com' }
    assert_match 'Escolha o e-mail', response.parsed_body['error']

    campaign.update!(email_template: template(@client))
    post send_test_campaign_path(campaign), params: { test_email: 'ana@example.com' }
    assert_match 'domínio de envio', response.parsed_body['error']
  end

  test 'send_test sends through SES with the TESTE prefix' do
    @client.update!(ses_verification_status: 'verified')
    campaign = @client.campaigns.create!(email_template: template(@client))
    calls = []
    sender = Object.new
    sender.define_singleton_method(:call) do |**args|
      calls << args
      true
    end

    Ses::SendEmailService.stub(:new, ->(_client) { sender }) do
      post send_test_campaign_path(campaign), params: { test_email: 'ana@example.com' }
    end

    assert_response :success
    assert_equal 'ana@example.com', calls.first[:to]
    assert_equal '[TESTE] Oi', calls.first[:subject]
  end

  def ready_campaign(subscribed: true)
    @client.update!(ses_verification_status: 'verified')
    segment = @client.segments.create!(name: 'Lista', kind: 'static')
    customer = Customer.create!(first_name: 'Eu', email: 'eu@example.com', shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, email: 'eu@example.com', refreshed_at: Time.current,
                            email_marketing_state: (subscribed ? 'subscribed' : 'not_subscribed'))
    SegmentMembership.create!(segment:, customer:)
    @client.campaigns.create!(name: 'Verão', segment:, email_template: template(@client))
  end

  test 'schedule confirms the campaign, records who did it and wakes up the dispatch' do
    campaign = ready_campaign

    assert_enqueued_with(job: Campaigns::DispatchJob, args: [campaign.id]) do
      post schedule_campaign_path(campaign)
    end

    campaign.reload
    assert_redirected_to campaigns_path
    assert_equal 'scheduled', campaign.status
    assert campaign.next_run_at.present? && campaign.published_at.present?
    assert campaign.published_by.present?
    assert_nil campaign.acknowledged_not_subscribed
  end

  test 'schedule needs the confirmation when part of the audience did not accept promotions' do
    campaign = ready_campaign(subscribed: false)

    post schedule_campaign_path(campaign)
    assert_redirected_to edit_campaign_path(campaign)
    assert campaign.reload.draft?

    post schedule_campaign_path(campaign), params: { accept_not_subscribed: '1' }
    assert_equal 'scheduled', campaign.reload.status
    assert_equal 1, campaign.acknowledged_not_subscribed
  end

  test 'schedule refuses incomplete campaigns, empty audiences and unverified domains' do
    incomplete = @client.campaigns.create!
    post schedule_campaign_path(incomplete)
    assert_match 'Falta', flash[:alert]

    campaign = ready_campaign
    campaign.segment.segment_memberships.destroy_all
    post schedule_campaign_path(campaign)
    assert_match 'não tem ninguém', flash[:alert]

    other = ready_campaign
    @client.update!(ses_verification_status: 'unverified')
    post schedule_campaign_path(other)
    assert_match 'domínio', flash[:alert]
    assert other.reload.draft?
  end

  test 'cancel stops a running campaign but not a finished one' do
    running = @client.campaigns.create!(status: 'sending', next_run_at: 1.minute.from_now)
    finished = @client.campaigns.create!(status: 'sent')

    post cancel_campaign_path(running)
    assert_equal 'cancelled', running.reload.status
    assert_nil running.next_run_at

    post cancel_campaign_path(finished)
    assert_equal 'sent', finished.reload.status
  end

  test 'the review button is enabled by the summary only when everything is ready' do
    campaign = ready_campaign

    patch campaign_path(campaign), params: { campaign: { name: 'Verão' } }, as: :json
    assert_equal true, response.parsed_body['ready']

    incomplete = @client.campaigns.create!
    patch campaign_path(incomplete), params: { campaign: { name: 'Só o nome' } }, as: :json
    assert_equal false, response.parsed_body['ready']
  end
end
