require 'test_helper'

class DispatchJobTest < ActiveJob::TestCase
  class FakeSender
    attr_reader :calls

    def initialize(client, failing: {})
      @client = client
      @failing = failing
      @calls = []
    end

    def call(to:, **args)
      raise @failing[to] if @failing[to]

      @calls << { to:, **args }
      MessageUsage.track!(@client, 'email')
      true
    end
  end

  MONDAY = Time.zone.local(2026, 11, 16, 10, 0)

  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             ses_verification_status: 'verified')
    @template = EmailTemplate.create!(client: @client, name: 'Modelo', subject: 'Oi {nome}',
                                      blocks: [{ 'type' => 'heading', 'text' => 'Olá {nome}' }])
    @segment = @client.segments.create!(name: 'Lista', kind: 'static')
  end

  def person(name, email)
    customer = Customer.create!(first_name: name, email:, shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, name:, email:, refreshed_at: Time.current)
    SegmentMembership.create!(segment: @segment, customer:)
  end

  def campaign(**attrs)
    @client.campaigns.create!({ name: 'Verão', email_template: @template, segment: @segment, status: 'scheduled',
                                next_run_at: 1.minute.ago }.merge(attrs))
  end

  def run_job(campaign, sender: FakeSender.new(@client), batch: nil)
    job = Campaigns::DispatchJob.new
    job.stub(:throttle, 0) do
      job.stub(:batch_size, batch || Campaigns::DispatchJob::BATCH_SIZE) do
        Ses::SendEmailService.stub(:new, ->(_client) { sender }) { job.perform(campaign.id) }
      end
    end
    sender
  end

  def freeze_for(campaign, emails)
    emails.each { |email| campaign.recipients.create!(email:, name: email.split('@').first) }
    campaign.update!(audience_frozen_at: Time.current, status: 'sending', recipients_count: emails.size)
  end

  test 'freezes the audience, sends to everyone, counts and finishes' do
    %w[ana bia caio].each { |name| person(name.capitalize, "#{name}@example.com") }
    campaign = campaign()

    sender = run_job(campaign)
    campaign.reload

    assert_equal %w[ana@example.com bia@example.com caio@example.com], sender.calls.map { |call| call[:to] }.sort
    assert_equal 'sent', campaign.status
    assert_equal 3, campaign.recipients_count
    assert_equal 3, campaign.sent_count
    assert campaign.audience_frozen_at.present? && campaign.finished_at.present?
    assert_nil campaign.next_run_at
    assert_equal 'Oi Ana', sender.calls.find { |call| call[:to] == 'ana@example.com' }[:subject]
    assert_match 'descadastrar', sender.calls.first[:unsubscribe_url]
  end

  test 'people on the opt-out list are left out of the frozen audience' do
    person('Ana', 'ana@example.com')
    person('Bia', 'bia@example.com')
    @client.email_suppressions.create!(email: 'bia@example.com', source: 'manual')
    campaign = campaign()

    sender = run_job(campaign)

    assert_equal ['ana@example.com'], sender.calls.map { |call| call[:to] }
    assert_equal 1, campaign.reload.recipients_count
  end

  test 'someone who opts out after the audience was frozen is blocked and not sent' do
    campaign = campaign()
    freeze_for(campaign, %w[ana@example.com bia@example.com])
    @client.email_suppressions.create!(email: 'bia@example.com', source: 'unsubscribe_link')

    sender = run_job(campaign)
    campaign.reload

    assert_equal ['ana@example.com'], sender.calls.map { |call| call[:to] }
    assert_equal 1, campaign.sent_count
    assert_equal 1, campaign.blocked_count
    assert_equal 'sent', campaign.status
  end

  test 'a failing address is recorded and the next ones still go' do
    campaign = campaign()
    freeze_for(campaign, %w[ana@example.com bia@example.com caio@example.com])
    error = Aws::SESV2::Errors::MessageRejected.new(nil, 'Email address is not valid')

    sender = run_job(campaign, sender: FakeSender.new(@client, failing: { 'bia@example.com' => error }))
    campaign.reload

    assert_equal 2, sender.calls.size
    assert_equal 1, campaign.failed_count
    assert_match 'not valid', campaign.recipients.find_by(email: 'bia@example.com').error
    assert_equal 'sent', campaign.status
  end

  test 'pauses at the daily limit and resumes at 8am the next day' do
    travel_to MONDAY do
      @client.update!(daily_email_limit: 2)
      4.times { |i| person("P#{i}", "p#{i}@example.com") }
      campaign = campaign()

      sender = run_job(campaign)
      campaign.reload

      assert_equal 2, sender.calls.size
      assert_equal 'paused', campaign.status
      assert_equal Time.zone.local(2026, 11, 17, 8, 0), campaign.next_run_at
      assert_equal 2, campaign.recipients.where(status: 'pending').count
    end
  end

  test 'waits for the next opening when the send window is closed' do
    travel_to Time.zone.local(2026, 11, 16, 14, 0) do
      campaign = campaign(send_mode: 'window', window_days: [1, 3], window_from: '08:00', window_to: '12:00')
      freeze_for(campaign, %w[ana@example.com])

      sender = run_job(campaign)
      campaign.reload

      assert_empty sender.calls
      assert_equal 'sending', campaign.status
      assert_equal Time.zone.local(2026, 11, 18, 8, 0), campaign.next_run_at
    end
  end

  test 'a full batch schedules another run right away' do
    3.times { |i| person("P#{i}", "p#{i}@example.com") }
    campaign = campaign()

    assert_enqueued_with(job: Campaigns::DispatchJob, args: [campaign.id]) do
      run_job(campaign, batch: 2)
    end

    campaign.reload
    assert_equal 2, campaign.sent_count
    assert_equal 'sending', campaign.status
    assert_in_delta Time.current.to_f, campaign.next_run_at.to_f, 5
  end

  test 'does not send a cancelled campaign nor one that is not due yet' do
    person('Ana', 'ana@example.com')
    cancelled = campaign(status: 'cancelled')
    future = campaign(next_run_at: 1.hour.from_now)

    assert_empty run_job(cancelled).calls
    assert_empty run_job(future).calls
    assert_nil future.reload.audience_frozen_at
  end

  test 'a second run does not send again to people who already received it' do
    person('Ana', 'ana@example.com')
    campaign = campaign()

    run_job(campaign)
    campaign.update!(status: 'sending', next_run_at: 1.minute.ago)
    sender = run_job(campaign)

    assert_empty sender.calls
    assert_equal 1, campaign.reload.sent_count
  end

  test 'pauses when the sending domain is not verified' do
    @client.update!(ses_verification_status: 'unverified')
    person('Ana', 'ana@example.com')
    campaign = campaign()

    sender = run_job(campaign)

    assert_empty sender.calls
    assert_equal 'paused', campaign.reload.status
    assert campaign.next_run_at > Time.current
  end

  test 'pauses without a date when the template was deleted' do
    person('Ana', 'ana@example.com')
    campaign = campaign()
    @template.destroy

    sender = run_job(campaign)
    campaign.reload

    assert_empty sender.calls
    assert_equal 'paused', campaign.status
    assert_nil campaign.next_run_at
  end
end
