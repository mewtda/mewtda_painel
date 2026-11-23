require 'test_helper'

class CampaignTest < ActiveSupport::TestCase
  NOW = Time.zone.local(2026, 11, 16, 10, 0)

  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                             whatsapp_cloud_access_token: 't')
  end

  def template(client = @client)
    EmailTemplate.create!(client:, name: 'Modelo', subject: 'Oi', blocks: [{ 'type' => 'heading', 'text' => 'Oi' }])
  end

  def wa_template(status: 'approved')
    @client.whatsapp_templates.create!(label: "Black #{SecureRandom.hex(2)}", body: 'Oi', status:)
  end

  def segment(client = @client)
    client.segments.create!(name: "Todos #{SecureRandom.hex(2)}", kind: 'static')
  end

  def ready_campaign(**attrs)
    campaign = @client.campaigns.create!({ name: 'Black', segment_ids: [segment.id] }.merge(attrs))
    campaign.messages.create!(channel: 'email', email_template: template)
    campaign
  end

  test 'a new campaign is a draft that is missing every step' do
    campaign = @client.campaigns.create!

    assert campaign.draft?
    assert_equal 'Rascunho', campaign.status_label
    assert campaign.email_enabled
    refute campaign.whatsapp_enabled
    assert_includes campaign.missing_steps, 'Dê um nome à campanha'
    assert_includes campaign.missing_steps, 'Escolha para quem enviar'
    assert_includes campaign.missing_steps, 'Adicione uma mensagem de e-mail'
  end

  test 'a campaign with name, segment and an e-mail message is complete' do
    assert_empty ready_campaign.missing_steps
  end

  test 'segments from another store are rejected' do
    campaign = @client.campaigns.new(segment_ids: [segment(Client.create!(name: 'Outra', email: 'o@example.com')).id])
    refute campaign.valid?
  end

  test 'whatsapp needs an approved template and the official API' do
    campaign = ready_campaign(whatsapp_enabled: true)
    campaign.messages.create!(channel: 'whatsapp', whatsapp_template: wa_template(status: 'pending'))

    assert(campaign.reload.missing_steps.any? { |s| s.include?('aprovado') })

    @client.update!(whatsapp_cloud_access_token: nil)
    assert(campaign.reload.missing_steps.any? { |s| s.include?('API Oficial') })
  end

  test 'disabled channels do not count' do
    campaign = ready_campaign
    campaign.messages.create!(channel: 'whatsapp', whatsapp_template: wa_template(status: 'pending'))
    assert_empty campaign.reload.missing_steps
    assert_equal ['email'], campaign.active_messages.map(&:channel)
    campaign.update!(email_enabled: false)
    assert_includes campaign.missing_steps, 'Ative o e-mail ou o WhatsApp'
  end

  test 'a message date in the past is a missing step' do
    campaign = ready_campaign
    campaign.messages.first.update!(send_at: 1.hour.ago)
    assert(campaign.reload.missing_steps.any? { |s| s.include?('já passou') })
  end

  test 'messages are ordered with "as soon as confirmed" first, then by date' do
    campaign = ready_campaign
    later = campaign.messages.create!(channel: 'email', email_template: template, send_at: 3.days.from_now)
    sooner = campaign.messages.create!(channel: 'email', email_template: template, send_at: 1.day.from_now)
    assert_equal [campaign.messages.first.send_at, sooner.send_at, later.send_at], campaign.reload.messages.map(&:send_at)
  end

  test 'timing summary covers every active message' do
    campaign = @client.campaigns.create!
    assert_equal 'Adicione as mensagens', campaign.timing_summary
    campaign.messages.create!(channel: 'email', email_template: template)
    assert_equal 'Assim que você confirmar', campaign.reload.timing_summary
    campaign.messages.first.update!(send_at: Time.zone.local(2026, 11, 27, 10, 0))
    assert_equal '27/11/2026 às 10:00', campaign.reload.timing_summary
    campaign.messages.create!(channel: 'email', email_template: template, send_at: Time.zone.local(2026, 11, 29, 18, 0))
    campaign.messages.create!(channel: 'email', email_template: template, send_at: Time.zone.local(2026, 11, 28, 9, 0))
    assert_equal '3 mensagens · 27/11 10:00 a 29/11 18:00', campaign.reload.timing_summary
  end

  test 'status is derived from the messages' do
    campaign = ready_campaign(status: 'scheduled')
    first = campaign.messages.first
    second = campaign.messages.create!(channel: 'email', email_template: template, send_at: NOW + 2.days)

    first.update!(status: 'scheduled', next_run_at: NOW + 1.day)
    second.update!(status: 'scheduled', next_run_at: NOW + 2.days)
    campaign.refresh_from_messages!
    assert_equal 'scheduled', campaign.status
    assert_equal NOW + 1.day, campaign.next_run_at

    first.update!(status: 'sending', recipients_count: 10, sent_count: 4, started_at: NOW)
    campaign.refresh_from_messages!
    assert_equal 'sending', campaign.status
    assert_equal 10, campaign.recipients_count
    assert_equal NOW, campaign.started_at

    first.update!(status: 'sent', sent_count: 10, finished_at: NOW + 1.hour)
    second.update!(status: 'sent', recipients_count: 8, sent_count: 7, failed_count: 1, finished_at: NOW + 2.days)
    campaign.refresh_from_messages!
    assert_equal 'sent', campaign.status
    assert_equal [18, 17, 1], [campaign.recipients_count, campaign.sent_count, campaign.failed_count]
    assert_equal NOW + 2.days, campaign.finished_at
    assert_nil campaign.next_run_at
  end

  test 'cancel! cancels pending messages and keeps sent ones' do
    campaign = ready_campaign(status: 'sending')
    campaign.messages.first.update!(status: 'sent')
    pending = campaign.messages.create!(channel: 'email', email_template: template, status: 'scheduled', send_at: 1.day.from_now)
    campaign.cancel!
    assert_equal 'cancelled', pending.reload.status
    assert_equal 'sent', campaign.messages.first.status
    assert_equal 'cancelled', campaign.reload.status
  end

  test 'progress and status notes tell the shop what is going on' do
    campaign = @client.campaigns.create!(status: 'paused', recipients_count: 6009, sent_count: 5000, failed_count: 1,
                                         blocked_count: 3, next_run_at: Time.zone.local(2026, 11, 17, 8, 0))

    assert_equal '5000 de 6009 enviados · 1 falha · 3 bloqueios', campaign.progress_label
    assert_equal 'Continua em 17/11 às 08:00', campaign.status_note(NOW)
    assert_equal 'Enviando agora', campaign.tap { |c| c.next_run_at = NOW - 1.minute }.status_note(NOW)
    assert_equal 'Enviando agora', @client.campaigns.create!(status: 'sending', next_run_at: NOW + 5.minutes).status_note(NOW)
    assert_equal 'Próxima mensagem em 16/11 às 17:00',
                 @client.campaigns.create!(status: 'scheduled', next_run_at: NOW + 7.hours).status_note(NOW)
    assert_nil @client.campaigns.create!(status: 'sent').status_note
  end

  test 'only running campaigns can be cancelled' do
    assert @client.campaigns.new(status: 'paused').cancelable?
    assert_not @client.campaigns.new(status: 'draft').cancelable?
    assert_not @client.campaigns.new(status: 'sent').cancelable?
  end

  test 'refresh_from_messages! runs under a row lock' do
    campaign = ready_campaign(status: 'scheduled')
    campaign.messages.first.update!(status: 'scheduled', next_run_at: NOW)
    locked = false
    campaign.stub(:with_lock, ->(&block) { locked = true and block.call }) { campaign.refresh_from_messages! }
    assert locked
  end

  test 'a cancelled campaign stays cancelled even if a message had already been sent' do
    campaign = ready_campaign(status: 'sending')
    campaign.messages.first.update!(status: 'sent')
    campaign.messages.create!(channel: 'email', email_template: template, status: 'scheduled', send_at: 1.day.from_now)
    campaign.cancel!
    campaign.refresh_from_messages!
    assert_equal 'cancelled', campaign.reload.status
  end

  test 'choosing "date and time" without filling them is a missing step' do
    campaign = ready_campaign
    message = campaign.messages.to_a.first
    message.assign_attributes(send_now: '0', send_on: '', send_time: '')
    message.valid?
    assert_nil message.send_at
    assert(campaign.missing_steps.any? { |s| s.include?('data e a hora') })
  end

  # Cenário da Black: msg 1 com boas-vindas já terminada, msg 2 enviada sem boas-vindas,
  # msg 3 agendada antes do novo prazo e msg 4 depois dele.
  def black_campaign(now)
    campaign = ready_campaign(status: 'sent')
    welcome = campaign.messages.first
    sent_once = campaign.messages.create!(channel: 'email', email_template: template)
    welcome.update_columns(status: 'sent', audience_frozen_at: now - 1.day, started_at: now - 1.day,
                           finished_at: now - 10.minutes, continuous_until: now - 10.minutes)
    sent_once.update_columns(status: 'sent', send_at: now - 1.hour, audience_frozen_at: now - 1.hour,
                             finished_at: now - 1.hour)
    later = campaign.messages.create!(channel: 'email', email_template: template, status: 'scheduled',
                                      send_at: now + 1.hour, next_run_at: now + 1.hour)
    after = campaign.messages.create!(channel: 'email', email_template: template, status: 'scheduled',
                                      send_at: now + 3.days, next_run_at: now + 3.days)
    [campaign, welcome, sent_once, later, after]
  end

  test 'welcome_until! extends the welcome and covers messages not sent yet, leaving the others alone' do
    campaign, welcome, sent_once, later, after = black_campaign(NOW)
    deadline = NOW + 2.hours

    assert_equal 2, campaign.welcome_until!(deadline, NOW)

    welcome.reload
    assert_equal [deadline, 'scheduled', NOW, nil],
                 [welcome.continuous_until, welcome.status, welcome.next_run_at, welcome.finished_at]
    assert_equal [deadline, 'scheduled', NOW + 1.hour], [later.reload.continuous_until, later.status, later.next_run_at]
    assert_nil sent_once.reload.continuous_until
    assert_equal 'sent', sent_once.status
    assert_nil after.reload.continuous_until
    assert_equal 'scheduled', campaign.reload.status
  end

  test 'welcome_until! does not touch a message that is sending right now, other than the deadline' do
    campaign, welcome, = black_campaign(NOW)
    welcome.update_columns(status: 'sending', next_run_at: NOW + 5.minutes, finished_at: nil)

    campaign.welcome_until!(NOW + 2.hours, NOW)

    assert_equal ['sending', NOW + 5.minutes, NOW + 2.hours],
                 welcome.reload.slice(:status, :next_run_at, :continuous_until).values
  end

  test 'welcome_until! ignores cancelled messages' do
    campaign, welcome, = black_campaign(NOW)
    welcome.update_columns(status: 'cancelled')

    assert_equal 1, campaign.welcome_until!(NOW + 2.hours, NOW)
    assert_equal NOW - 10.minutes, welcome.reload.continuous_until
  end

  test 'on confirmation, messages that go out before the welcome deadline inherit it' do
    campaign = ready_campaign
    first = campaign.messages.first
    first.update!(continuous_until: NOW + 4.hours)
    before = campaign.messages.create!(channel: 'email', email_template: template, send_at: NOW + 3.hours)
    on_time = campaign.messages.create!(channel: 'email', email_template: template, send_at: NOW + 4.hours)
    later = campaign.messages.create!(channel: 'email', email_template: template, send_at: NOW + 1.day)
    off = campaign.messages.create!(channel: 'whatsapp', send_at: NOW + 1.hour)
    campaign.messages.reload

    assert_equal NOW + 4.hours, campaign.inherited_welcome_until(campaign.messages.find { |m| m.id == before.id })

    campaign.inherit_welcome!

    assert_equal NOW + 4.hours, before.reload.continuous_until
    assert_nil on_time.reload.continuous_until
    assert_nil later.reload.continuous_until
    assert_nil off.reload.continuous_until
  end

  test 'without a welcome message nothing is inherited' do
    campaign = ready_campaign
    campaign.messages.create!(channel: 'email', email_template: template, send_at: NOW + 1.hour)

    campaign.inherit_welcome!

    assert(campaign.messages.reload.none?(&:continuous?))
  end
end
