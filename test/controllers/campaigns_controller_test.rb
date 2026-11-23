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

  test 'details shows the campaign summary with download links only when there is something to download' do
    campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sent', recipients_count: 3, sent_count: 2, failed_count: 1)

    get details_campaign_path(campaign)

    assert_response :success
    assert_match 'Black Friday', response.body
    assert_match 'Baixar lista', response.body
    assert_includes response.body, recipients_campaign_path(campaign, status: 'sent')
    assert_includes response.body, recipients_campaign_path(campaign, status: 'failed')
    assert_not_includes response.body, recipients_campaign_path(campaign, status: 'blocked')
  end

  test 'deliveries lists the audience with each message status and exports a spreadsheet' do
    customer = Customer.create!(first_name: 'Ana', email: 'ana@example.com', shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, email: 'ana@example.com', phone: '(31) 99999-0001', name: 'Ana',
                            refreshed_at: Time.current)
    segment = @client.segments.create!(name: 'Black', kind: 'static')
    SegmentMembership.create!(segment:, customer_id: customer.id)
    campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sent', started_at: 1.hour.ago)
    campaign.campaign_segments.create!(segment:)
    message = campaign.messages.create!(channel: 'whatsapp', status: 'sent', audience_frozen_at: 1.hour.ago)
    campaign.recipients.create!(message:, channel: 'whatsapp', customer_id: customer.id, phone: '+5531999990001',
                                status: 'sent', sent_at: 30.minutes.ago)

    get deliveries_campaign_path(campaign)

    assert_response :success
    assert_match 'Ana', response.body
    assert_match 'Enviada', response.body
    assert_match 'Receberam alguma mensagem (1)', response.body

    get deliveries_campaign_path(campaign, canal: 'email')

    assert_response :success
    assert_match 'Receberam algum e-mail (0)', response.body
    assert_match 'Esta campanha não tem mensagens de e-mail', response.body
    assert_no_match 'crm-tag--success">Enviada', response.body

    get deliveries_campaign_path(campaign, format: 'xlsx')

    assert_response :success
    assert_equal Spreadsheets::Base::CONTENT_TYPE, response.media_type
  end

  test 'details of another store campaign is not found' do
    other = build_client.campaigns.create!(name: 'Alheia', status: 'sent')

    get details_campaign_path(other)

    assert_redirected_to campaigns_path
  end

  test 'recipients downloads a spreadsheet of the chosen status' do
    campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sent')
    campaign.recipients.create!(email: 'ana@example.com', name: 'Ana', status: 'sent', sent_at: Time.current)
    campaign.recipients.create!(email: 'bia@example.com', status: 'failed', error: 'caixa cheia')

    get recipients_campaign_path(campaign, status: 'failed')

    assert_response :success
    assert_equal 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', response.media_type
    sheet = RubyXL::Parser.parse_buffer(response.body)[0]
    headers = sheet[0].cells.map(&:value)
    assert_equal %w[Nome E-mail], headers.first(2)
    assert_equal 'Motivo', headers.last
    assert_includes headers, 'Total gasto'
    assert_equal 'bia@example.com', sheet[1][1].value
    assert_equal 'caixa cheia', sheet[1].cells.last.value
    assert_nil sheet[2]
  end

  test 'recipients spreadsheet carries the customer profile data' do
    campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sent')
    customer = Customer.create!(shopify_customer_id: 987, email: 'ana@example.com', first_name: 'Ana')
    CustomerProfile.create!(client: @client, customer:, name: 'Ana Souza', email: 'ana@example.com', city: 'Santos', state: 'SP',
                            orders_count: 3, total_spent: 450, avg_ticket: 150, refreshed_at: Time.current)
    campaign.recipients.create!(email: 'ana@example.com', name: 'Ana Souza', customer_id: customer.id, status: 'sent', sent_at: Time.current)

    get recipients_campaign_path(campaign, status: 'sent')

    sheet = RubyXL::Parser.parse_buffer(response.body)[0]
    headers = sheet[0].cells.map(&:value)
    row = sheet[1].cells.map(&:value)
    assert_equal 'Santos', row[headers.index('Cidade')]
    assert_equal 3, row[headers.index('Nº de compras')]
    assert_equal 450.0, row[headers.index('Total gasto')]
    assert_match %r{\A\d{2}/\d{2}/\d{4} \d{2}:\d{2}\z}, row.last
  end

  test 'recipients rejects an unknown status' do
    campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sent')

    get recipients_campaign_path(campaign, status: 'pending')

    assert_redirected_to campaigns_path
  end

  test 'index links to the performance of campaigns that already started' do
    started = @client.campaigns.create!(name: 'Enviada', status: 'sent', started_at: 1.day.ago)
    pending = @client.campaigns.create!(name: 'Agendada', status: 'scheduled')

    get campaigns_path

    assert_includes response.body, campaign_performance_path(campanha: started.id)
    assert_not_includes response.body, campaign_performance_path(campanha: pending.id)
  end

  test 'index searches campaigns by name' do
    @client.campaigns.create!(name: 'Promoção de verão')
    @client.campaigns.create!(name: 'Dia das mães')

    get campaigns_path(q: 'verão')

    assert_match 'Promoção de verão', response.body
    assert_no_match 'Dia das mães', response.body
  end

  test 'index filters by channel through the messages' do
    by_email = @client.campaigns.create!(name: 'Por e-mail')
    by_email.messages.create!(channel: 'email')
    by_whatsapp = @client.campaigns.create!(name: 'Pelo WhatsApp', whatsapp_enabled: true, email_enabled: false)
    by_whatsapp.messages.create!(channel: 'whatsapp')

    get campaigns_path(canal: 'whatsapp')
    assert_match 'Pelo WhatsApp', response.body
    assert_no_match 'Por e-mail', response.body

    get campaigns_path(canal: 'nenhum')
    assert_match 'Por e-mail', response.body
    assert_match 'Pelo WhatsApp', response.body
  end

  test 'index shows the active channels and the chosen segments' do
    campaign = @client.campaigns.create!(name: 'Black', whatsapp_enabled: true,
                                         segment_ids: [@client.segments.create!(name: 'VIPs', kind: 'static').id])
    campaign.messages.create!(channel: 'whatsapp')

    get campaigns_path

    assert_match 'VIPs', response.body
    assert_match 'fa-whatsapp', response.body
  end

  test 'details of a migrated e-mail campaign show the same numbers per message' do
    campaign = @client.campaigns.create!(name: 'Antiga', status: 'sent', recipients_count: 3, sent_count: 2, failed_count: 1,
                                         started_at: 1.day.ago)
    message = campaign.messages.create!(channel: 'email', email_template: template(@client), status: 'sent',
                                        recipients_count: 3, sent_count: 2, failed_count: 1)

    get details_campaign_path(campaign)

    assert_response :success
    assert_match 'Modelo', response.body
    assert_includes response.body, ERB::Util.html_escape(recipients_campaign_path(campaign, status: 'sent', message_id: message.id))
    assert_includes response.body, ERB::Util.html_escape(recipients_campaign_path(campaign, status: 'failed', message_id: message.id))
    assert_match '2 de 3 enviados', response.body
  end

  test 'details groups the messages by channel with a welcome that keeps sending shown as active' do
    campaign = @client.campaigns.create!(name: 'Black', status: 'scheduled', started_at: 1.hour.ago)
    campaign.messages.create!(channel: 'whatsapp', status: 'scheduled', position: 0, started_at: 1.hour.ago,
                              continuous_until: 1.day.from_now, recipients_count: 2, sent_count: 2)
    campaign.messages.create!(channel: 'email', email_template: template(@client), status: 'scheduled', position: 1,
                              send_at: 1.day.from_now)

    get details_campaign_path(campaign)

    assert_response :success
    assert_equal 2, response.body.scan('class="ec-channel"').size
    assert_operator response.body.index('fa-envelope'), :<, response.body.rindex('fa-whatsapp')
    assert_match 'Boas-vindas ativa', response.body
    assert_no_match 'ec-details__message"', response.body
  end

  test 'create makes a draft and goes to the editor' do
    assert_difference '@client.campaigns.count', 1 do
      post campaigns_path
    end

    campaign = @client.campaigns.last
    assert_redirected_to edit_campaign_path(campaign)
    assert campaign.draft?
  end

  def segment_with(email: 'eu@example.com', phone: nil, subscribed: true, name: 'Lista')
    segment = @client.segments.create!(name: "#{name} #{SecureRandom.hex(2)}", kind: 'static')
    customer = Customer.create!(first_name: 'Eu', email:, shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, email:, phone:, name: 'Eu Mesmo', refreshed_at: Time.current,
                            email_marketing_state: (subscribed ? 'subscribed' : 'not_subscribed'))
    SegmentMembership.create!(segment:, customer:)
    segment
  end

  def configure_whatsapp!
    @client.update!(whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                    whatsapp_cloud_access_token: 'tok')
  end

  def wa_template(status: 'approved')
    @client.whatsapp_templates.create!(label: "Black #{SecureRandom.hex(2)}", body: 'Oi {{1}}', body_example: 'Maria', status:)
  end

  test 'edit renders the e-mail and WhatsApp tabs for a draft' do
    configure_whatsapp!
    campaign = @client.campaigns.create!(whatsapp_enabled: true)
    email = campaign.messages.create!(channel: 'email', email_template: template(@client), send_at: 2.days.from_now)
    whatsapp = campaign.messages.create!(channel: 'whatsapp', whatsapp_template: wa_template)

    get edit_campaign_path(campaign)

    assert_response :success
    assert_match 'Mensagens', response.body
    assert_match 'WhatsApp', response.body
    assert_match 'entra na sua fatura do mês', response.body
    assert_includes response.body, "campaign[messages_attributes][#{email.id}][send_on]"
    assert_includes response.body, "campaign[messages_attributes][#{whatsapp.id}][whatsapp_template_id]"
  end

  test 'add_message creates a draft message of the channel and returns its row' do
    campaign = @client.campaigns.create!

    post add_message_campaign_path(campaign), params: { channel: 'whatsapp' }

    assert_response :success
    message = campaign.messages.sole
    assert_equal ['whatsapp', 'draft'], [message.channel, message.status]
    assert_includes response.body, "campaign[messages_attributes][#{message.id}][whatsapp_template_id]"
  end

  test 'remove_message deletes a message of a draft' do
    campaign = @client.campaigns.create!
    message = campaign.messages.create!(channel: 'email')

    delete remove_message_campaign_path(campaign, message_id: message.id), as: :json

    assert_response :success
    assert_empty campaign.messages.reload
  end

  test 'saving two segments and two messages (WhatsApp and e-mail) persists and is ready' do
    configure_whatsapp!
    @client.update!(ses_verification_status: 'verified')
    campaign = @client.campaigns.create!
    email = campaign.messages.create!(channel: 'email')
    whatsapp = campaign.messages.create!(channel: 'whatsapp')
    first = segment_with(email: 'a@example.com', phone: '16992375432')
    second = segment_with(email: 'b@example.com', phone: nil)
    approved = wa_template

    patch campaign_path(campaign), as: :json, params: { campaign: {
      name: 'Black', segment_ids: ['', first.id, second.id], email_enabled: '1', whatsapp_enabled: '1',
      messages_attributes: {
        email.id => { id: email.id, email_template_id: template(@client).id, send_now: '1' },
        whatsapp.id => { id: whatsapp.id, whatsapp_template_id: approved.id, send_now: '0',
                         send_on: 2.days.from_now.to_date.iso8601, send_time: '10:00' }
      }
    } }

    assert_response :success
    body = response.parsed_body
    assert_equal [], body['missing']
    assert_equal true, body['ready']
    assert_equal [first.id, second.id].sort, campaign.reload.segment_ids.sort
    assert_equal 2, body['channels']['email']['recipients']
    assert_equal 1, body['channels']['whatsapp']['recipients']
    assert_equal true, body['channels']['whatsapp']['configured']
    assert_equal 'R$ 0,10', body['channels']['whatsapp']['cost']
    assert_nil email.reload.send_at
    assert_equal '10:00', whatsapp.reload.send_at.strftime('%H:%M')
    assert_equal 2, body['messages'].size
  end

  test 'saving only the welcome or date fields of a message persists them' do
    campaign = @client.campaigns.create!(name: 'Black', whatsapp_enabled: true, email_enabled: false)
    message = campaign.messages.create!(channel: 'whatsapp', whatsapp_template: wa_template)

    patch campaign_path(campaign), as: :json, params: { campaign: { messages_attributes: {
      message.id => { id: message.id, send_now: '1', continuous: '1', continuous_on: '2026-11-23', continuous_time: '14:00' }
    } } }
    assert_response :success
    assert_equal Time.zone.local(2026, 11, 23, 14, 0), message.reload.continuous_until

    patch campaign_path(campaign), as: :json, params: { campaign: { messages_attributes: {
      message.id => { id: message.id, send_now: '0', send_on: '2026-11-23', send_time: '09:00', continuous: '1',
                      continuous_on: '2026-11-23', continuous_time: '14:00' }
    } } }
    assert_equal Time.zone.local(2026, 11, 23, 9, 0), message.reload.send_at

    patch campaign_path(campaign), as: :json, params: { campaign: { messages_attributes: {
      message.id => { id: message.id, continuous: '0' }
    } } }
    assert_nil message.reload.continuous_until
  end

  test 'WhatsApp with a template still in review is missing the approval' do
    configure_whatsapp!
    campaign = @client.campaigns.create!(name: 'Black', segment_ids: [segment_with.id], whatsapp_enabled: true,
                                         email_enabled: false)
    message = campaign.messages.create!(channel: 'whatsapp', whatsapp_template: wa_template(status: 'pending'))

    patch campaign_path(campaign), params: { campaign: { name: 'Black' } }, as: :json

    assert(response.parsed_body['missing'].any? { |text| text.include?('aprovado') })
    assert_equal false, response.parsed_body['ready']
    assert message
  end

  test 'cost shows less than one cent for a tiny audience instead of zero' do
    campaign = @client.campaigns.create!(segment_ids: [segment_with.id])

    patch campaign_path(campaign), params: { campaign: { name: 'Teste' } }, as: :json

    assert_equal 1, response.parsed_body['channels']['email']['recipients']
    assert_equal 'menos de R$ 0,01', response.parsed_body['channels']['email']['cost']
  end

  test 'update rejects a segment from another store' do
    campaign = @client.campaigns.create!
    foreign = build_client.segments.create!(name: 'Alheio', kind: 'static')

    patch campaign_path(campaign), params: { campaign: { segment_ids: [foreign.id] } }, as: :json

    assert_response :unprocessable_entity
    assert_empty campaign.reload.segment_ids
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

  test 'preview renders the e-mail of the chosen message' do
    campaign = @client.campaigns.create!
    message = campaign.messages.create!(channel: 'email', email_template: template(@client))

    get preview_campaign_path(campaign, message_id: message.id)

    assert_response :success
    assert_match 'Oi', response.body
  end

  test 'send_test validates the address, the template and the domain' do
    campaign = @client.campaigns.create!
    message = campaign.messages.create!(channel: 'email')

    post send_test_campaign_path(campaign), params: { test_email: 'ruim', message_id: message.id }
    assert_response :unprocessable_entity

    post send_test_campaign_path(campaign), params: { test_email: 'ana@example.com', message_id: message.id }
    assert_match 'Escolha o e-mail', response.parsed_body['error']

    message.update!(email_template: template(@client))
    post send_test_campaign_path(campaign), params: { test_email: 'ana@example.com', message_id: message.id }
    assert_match 'domínio de envio', response.parsed_body['error']
  end

  test 'send_test sends through SES with the TESTE prefix' do
    @client.update!(ses_verification_status: 'verified')
    campaign = @client.campaigns.create!
    message = campaign.messages.create!(channel: 'email', email_template: template(@client))
    calls = []
    sender = Object.new
    sender.define_singleton_method(:call) do |**args|
      calls << args
      true
    end

    Ses::SendEmailService.stub(:new, ->(_client) { sender }) do
      post send_test_campaign_path(campaign), params: { test_email: 'ana@example.com', message_id: message.id }
    end

    assert_response :success
    assert_equal 'ana@example.com', calls.first[:to]
    assert_equal '[TESTE] Oi', calls.first[:subject]
  end

  test 'send_test_whatsapp sends the chosen template to the typed phone' do
    configure_whatsapp!
    campaign = @client.campaigns.create!
    approved = wa_template
    calls = []
    api = Object.new
    def api.configured? = true
    api.define_singleton_method(:send_template) { |**args| calls << args and 'wamid.T' }

    Whatsapp::Cloud::Api.stub(:new, ->(_client) { api }) do
      post send_test_whatsapp_campaign_path(campaign), params: { phone: '(16) 99237-5432', whatsapp_template_id: approved.id }
    end

    assert_response :success
    assert_equal [{ to: '+5516992375432', name: approved.name, language: 'pt_BR', body_params: ['Maria'] }], calls
  end

  test 'send_test_whatsapp refuses an invalid phone or a template not approved' do
    configure_whatsapp!
    campaign = @client.campaigns.create!

    post send_test_whatsapp_campaign_path(campaign), params: { phone: '123', whatsapp_template_id: wa_template.id }
    assert_response :unprocessable_entity

    post send_test_whatsapp_campaign_path(campaign), params: { phone: '16992375432', whatsapp_template_id: wa_template(status: 'pending').id }
    assert_match 'aprovado', response.parsed_body['error']
  end

  def ready_campaign(subscribed: true)
    @client.update!(ses_verification_status: 'verified')
    campaign = @client.campaigns.create!(name: 'Verão', segment_ids: [segment_with(subscribed:).id])
    campaign.messages.create!(channel: 'email', email_template: template(@client))
    campaign
  end

  test 'schedule confirms the campaign, records who did it and wakes up the dispatch' do
    campaign = ready_campaign
    message = campaign.messages.first

    assert_enqueued_with(job: Campaigns::DispatchJob, args: [message.id]) do
      post schedule_campaign_path(campaign)
    end

    campaign.reload
    assert_redirected_to campaigns_path
    assert_equal 'scheduled', campaign.status
    assert_equal 'scheduled', message.reload.status
    assert campaign.next_run_at.present? && campaign.published_at.present?
    assert campaign.published_by.present?
    assert_nil campaign.acknowledged_not_subscribed
  end

  test 'schedule plans each message at its time and only wakes up the ones due now' do
    configure_whatsapp!
    campaign = ready_campaign
    campaign.update!(whatsapp_enabled: true)
    campaign.segments.first.segment_memberships.first.customer.then do |customer|
      CustomerProfile.find_by(customer:).update!(phone: '16992375432')
    end
    later = 3.days.from_now.change(sec: 0)
    whatsapp = campaign.messages.create!(channel: 'whatsapp', whatsapp_template: wa_template, send_at: later)
    email = campaign.messages.find_by(channel: 'email')

    post schedule_campaign_path(campaign)

    assert_enqueued_jobs 1, only: Campaigns::DispatchJob
    assert_enqueued_with(job: Campaigns::DispatchJob, args: [email.id])
    assert_equal ['scheduled', later], [whatsapp.reload.status, whatsapp.next_run_at]
    assert_in_delta Time.current.to_f, email.reload.next_run_at.to_f, 5
  end

  test 'schedule cancels messages of a channel turned off' do
    campaign = ready_campaign
    off = campaign.messages.create!(channel: 'whatsapp', whatsapp_template: wa_template)

    post schedule_campaign_path(campaign)

    assert_equal 'cancelled', off.reload.status
    assert_equal 'scheduled', campaign.reload.status
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
    campaign.segments.first.segment_memberships.destroy_all
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
    pending = running.messages.create!(channel: 'email', status: 'scheduled', next_run_at: 1.day.from_now)
    finished = @client.campaigns.create!(status: 'sent')

    post cancel_campaign_path(running)
    assert_equal 'cancelled', running.reload.status
    assert_equal 'cancelled', pending.reload.status
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
