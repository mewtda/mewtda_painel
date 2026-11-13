require 'test_helper'

class ProcessCartRecoveryCampaignsJobTest < ActiveJob::TestCase
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @number = @client.whatsapp_connections.create!(name: 'Loja', state: 'connected')
  end

  def create_campaign(attrs = {})
    campaign = @client.campaigns.create!({
      name: 'Recuperação', kind: 'cart_recovery', message: 'Oi {nome}',
      start_date: Date.current - 1.day, end_date: Date.current + 1.year,
      send_delay_minutes: 60
    }.merge(attrs))
    Whatsapp::CampaignConnection.create!(campaign: campaign, connection: @number)
    campaign.update_column(:evolution_started_at, 3.days.ago)
    campaign
  end

  def create_checkout(attrs = {})
    @client.abandoned_checkouts.create!({
      shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999',
      checkout_created_at: Time.current
    }.merge(attrs))
  end

  test 'sends the first message once the delay has passed for a pending checkout' do
    create_campaign
    checkout = create_checkout(checkout_created_at: 2.hours.ago)

    assert_enqueued_with(job: SendCartRecoveryNotificationJob, args: [checkout.id, 'Oi {nome}', nil, 'first']) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'checkouts older than 24 hours never get the first message' do
    create_campaign
    create_checkout(checkout_created_at: 25.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryNotificationJob) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'modo teste só envia para o número de teste' do
    create_campaign(test_phone: '11 98888-7777')
    create_checkout(checkout_created_at: 2.hours.ago)
    mine = create_checkout(checkout_created_at: 2.hours.ago, phone: '+55 11 98888-7777')

    assert_enqueued_jobs 1, only: SendCartRecoveryNotificationJob do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
    assert_enqueued_with(job: SendCartRecoveryNotificationJob, args: [mine.id, 'Oi {nome}', nil, 'first'])
  end

  test 'does not send before the configured delay has passed' do
    create_campaign(send_delay_minutes: 120)
    create_checkout(checkout_created_at: 10.minutes.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryNotificationJob) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'sends the resend message when enabled and the resend delay has passed' do
    create_campaign(resend_enabled: true, resend_delay_hours: 24, resend_message: 'Volta, {nome}!')
    checkout = create_checkout(checkout_created_at: 2.days.ago, first_notified_at: 2.days.ago)

    assert_enqueued_with(job: SendCartRecoveryNotificationJob,
                         args: [checkout.id, 'Volta, {nome}!', nil, 'second']) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'skips clients without a connected number' do
    @number.update!(state: 'disconnected')
    create_campaign
    create_checkout(checkout_created_at: 2.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryNotificationJob) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end
end

class ProcessCartRecoveryEvolutionTest < ActiveJob::TestCase
  def setup
    @client = Client.create!(name: 'Loja Evo', email: "evo-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_provider: 'evolution')
    @campaign = @client.campaigns.create!(
      name: 'Recuperação', kind: 'cart_recovery', message: 'Oi {nome}',
      start_date: Date.current - 1.day, end_date: Date.current + 1.year, send_delay_minutes: 60
    )
  end

  def checkout(created_at)
    @client.abandoned_checkouts.create!(shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999',
                                        checkout_created_at: created_at)
  end

  def connect!
    conn = @client.whatsapp_connections.create!(name: 'A', state: 'connected')
    Whatsapp::CampaignConnection.create!(campaign: @campaign, connection: conn)
    conn
  end

  test 'evolution only sends checkouts created after the first number was linked' do
    old = checkout(3.hours.ago)
    connect!
    @campaign.reload.update_column(:evolution_started_at, 2.hours.ago)
    fresh = checkout(90.minutes.ago)

    assert_enqueued_jobs 1, only: SendCartRecoveryNotificationJob do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
    assert_enqueued_with(job: SendCartRecoveryNotificationJob, args: [fresh.id, 'Oi {nome}', nil, 'first'])
    assert_equal :pending, old.reload.status
  end

  test 'evolution without evolution_started_at sends nothing' do
    connect!
    @campaign.update_column(:evolution_started_at, nil)
    checkout(3.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryNotificationJob) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'evolution client without connected number sends nothing' do
    @client.whatsapp_connections.create!(name: 'A', state: 'disconnected')
    checkout(3.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryNotificationJob) do
      ProcessCartRecoveryCampaignsJob.perform_now(@client.id)
    end
  end

  test 'schedule.yml syncs abandoned checkouts and processes cart recovery' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    classes = schedule.values.map { |job| job['class'] }
    assert_includes classes, 'DailyAbandonedCheckoutsSyncJob'
    assert_includes classes, 'ProcessCartRecoveryCampaignsJob'
  end
end
