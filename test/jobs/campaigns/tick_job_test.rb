require 'test_helper'

class TickJobTest < ActiveJob::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  test 'wakes up only the campaigns that are due' do
    due = @client.campaigns.create!(status: 'scheduled', next_run_at: 1.minute.ago)
    resumed = @client.campaigns.create!(status: 'paused', next_run_at: 1.second.ago)
    @client.campaigns.create!(status: 'scheduled', next_run_at: 1.hour.from_now)
    @client.campaigns.create!(status: 'paused', next_run_at: nil)
    @client.campaigns.create!(status: 'draft')
    @client.campaigns.create!(status: 'sent', next_run_at: 1.minute.ago)

    Campaigns::TickJob.perform_now

    assert_enqueued_jobs 2, only: Campaigns::DispatchJob
    assert_enqueued_with(job: Campaigns::DispatchJob, args: [due.id])
    assert_enqueued_with(job: Campaigns::DispatchJob, args: [resumed.id])
  end
end
