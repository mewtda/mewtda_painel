require 'test_helper'

class CampaignTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def template(client = @client)
    EmailTemplate.create!(client:, name: 'Modelo', subject: 'Oi', blocks: [{ 'type' => 'heading', 'text' => 'Oi' }])
  end

  def segment(client = @client)
    client.segments.create!(name: 'Todos', kind: 'static')
  end

  test 'a new campaign is a draft that is missing every step' do
    campaign = @client.campaigns.create!

    assert campaign.draft?
    assert_equal 'Rascunho', campaign.status_label
    assert_includes campaign.missing_steps, 'Escolha o e-mail'
    assert_includes campaign.missing_steps, 'Escolha para quem enviar'
    assert_equal({ 'name' => false, 'template' => false, 'audience' => false, 'timing' => true }, campaign.step_done)
  end

  test 'steps are done when name, template, segment and timing are set' do
    campaign = @client.campaigns.create!(name: 'Verão', email_template: template, segment: segment)

    assert_empty campaign.missing_steps
    assert campaign.step_done.values.all?
  end

  test 'template and segment from another store are rejected' do
    other = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(4)}@example.com")
    campaign = @client.campaigns.new(email_template: template(other), segment: segment(other))

    assert_not campaign.valid?
    assert_includes campaign.errors.attribute_names, :email_template_id
    assert_includes campaign.errors.attribute_names, :segment_id
  end

  test 'scheduled date and time compose scheduled_at and the timing summary reads it' do
    campaign = @client.campaigns.create!(send_mode: 'scheduled', scheduled_on: '2026-12-01', scheduled_time: '09:30')

    assert_equal Time.zone.local(2026, 12, 1, 9, 30), campaign.scheduled_at
    assert_equal '01/12/2026 às 09:30', campaign.timing_summary
    assert_equal '2026-12-01', campaign.scheduled_on.to_s
  end

  test 'scheduled mode without a date is missing a step' do
    campaign = @client.campaigns.create!(send_mode: 'scheduled')

    assert_includes campaign.missing_steps, 'Escolha a data e a hora'
  end

  test 'window days are cleaned and the window drives the timing summary' do
    campaign = @client.campaigns.create!(send_mode: 'window', window_days: ['', '3', '1', '1', '9'],
                                               window_from: '08:00', window_to: '12:00')

    assert_equal [1, 3], campaign.window_days
    assert_equal 'Seg e Qua, das 08:00 às 12:00', campaign.timing_summary
    assert campaign.step_done['timing']
  end

  test 'window mode without days is missing a step and invalid hours are rejected' do
    campaign = @client.campaigns.create!(send_mode: 'window')

    assert_includes campaign.missing_steps, 'Escolha os dias e o horário'
    assert_not @client.campaigns.new(window_from: '25:00').valid?
  end

  test 'the channel defaults to e-mail and rejects unknown channels' do
    campaign = @client.campaigns.create!

    assert_equal 'email', campaign.channel
    assert_equal 'E-mail', campaign.channel_label
    assert_not @client.campaigns.new(channel: 'sms').valid?
  end

  test 'after the daily limit the campaign resumes at 8am the next day' do
    campaign = @client.campaigns.create!
    monday = Time.zone.local(2026, 11, 16, 15, 0)

    assert_equal Time.zone.local(2026, 11, 17, 8, 0), campaign.resume_at(monday)
    assert_equal 'Terça-feira, 17/11 às 08:00', campaign.resume_label(monday)
  end

  test 'with a send window it resumes at the next opening of the window' do
    campaign = @client.campaigns.create!(send_mode: 'window', window_days: [1, 3, 4], window_from: '09:30', window_to: '12:00')
    monday = Time.zone.local(2026, 11, 16, 11, 0)

    assert_equal Time.zone.local(2026, 11, 18, 9, 30), campaign.resume_at(monday)
    assert_equal 'Quarta-feira, 18/11, das 09:30 às 12:00', campaign.resume_label(monday)
  end

  test 'a campaign scheduled for another day starts then and resumes at 8am the day after' do
    campaign = @client.campaigns.create!(send_mode: 'scheduled', scheduled_on: '2026-11-20', scheduled_time: '14:00')
    monday = Time.zone.local(2026, 11, 16, 15, 0)

    assert_equal Time.zone.local(2026, 11, 20, 14, 0), campaign.first_send_at(monday)
    assert_equal 'Sexta-feira, 20/11 às 14:00', campaign.first_day_label(monday)
    assert_equal Time.zone.local(2026, 11, 21, 8, 0), campaign.resume_at(monday)
  end

  test 'a campaign scheduled in the past starts now' do
    campaign = @client.campaigns.create!(send_mode: 'scheduled', scheduled_on: '2026-11-10', scheduled_time: '09:00')
    monday = Time.zone.local(2026, 11, 16, 15, 0)

    assert_equal monday, campaign.first_send_at(monday)
    assert_equal 'Segunda-feira, 16/11 (hoje)', campaign.first_day_label(monday)
  end

  test 'progress and status notes tell the shop what is going on' do
    now = Time.zone.local(2026, 11, 16, 10, 0)
    campaign = @client.campaigns.create!(status: 'sending', recipients_count: 6009, sent_count: 5000, failed_count: 1,
                                         blocked_count: 3, next_run_at: Time.zone.local(2026, 11, 17, 8, 0))

    assert_equal '5000 de 6009 enviados · 1 falha · 3 bloqueios', campaign.progress_label
    assert_equal 'Continua em 17/11 às 08:00', campaign.status_note(now)
    assert_equal 'Enviando agora', campaign.tap { |c| c.next_run_at = now - 1.minute }.status_note(now)
    assert_equal 'Confira o e-mail e o público desta campanha', campaign.tap { |c| c.next_run_at = nil }.status_note(now)
    assert_nil @client.campaigns.create!(status: 'sent').status_note
  end

  test 'only running campaigns can be cancelled' do
    assert @client.campaigns.new(status: 'paused').cancelable?
    assert_not @client.campaigns.new(status: 'draft').cancelable?
    assert_not @client.campaigns.new(status: 'sent').cancelable?
  end
end
