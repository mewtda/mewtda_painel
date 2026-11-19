require 'test_helper'

class TickJobTest < ActiveJob::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @campaign = @client.campaigns.create!(status: 'scheduled')
  end

  def msg(**attrs) = @campaign.messages.create!(channel: 'email', **attrs)

  test 'wakes up only the messages that are due' do
    due = msg(status: 'scheduled', next_run_at: 1.minute.ago)
    resumed = msg(status: 'paused', next_run_at: 1.second.ago)
    msg(status: 'scheduled', next_run_at: 1.hour.from_now)
    msg(status: 'paused', next_run_at: nil)
    msg(status: 'draft')
    msg(status: 'sent', next_run_at: 1.minute.ago)

    Campaigns::TickJob.perform_now

    assert_enqueued_jobs 2, only: Campaigns::DispatchJob
    assert_enqueued_with(job: Campaigns::DispatchJob, args: [due.id])
    assert_enqueued_with(job: Campaigns::DispatchJob, args: [resumed.id])
  end
end
