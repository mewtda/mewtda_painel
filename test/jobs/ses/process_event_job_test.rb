require 'test_helper'

class Ses::ProcessEventJobTest < ActiveJob::TestCase
  test 'records the event carried by the SNS message' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    campaign = client.campaigns.create!(name: 'Black Friday', status: 'sent')
    payload = { 'eventType' => 'Open', 'open' => { 'timestamp' => '2026-11-14T11:00:00.000Z' },
                'mail' => { 'messageId' => 'm-1', 'tags' => { 'source' => ['campaign'], 'client_id' => [client.id.to_s],
                                                              'campaign_id' => [campaign.id.to_s] } } }

    assert_difference('EmailEvent.count', 1) { Ses::ProcessEventJob.perform_now(payload.to_json) }
  end

  test 'survives a malformed message' do
    assert_nothing_raised { Ses::ProcessEventJob.perform_now('não é json') }
    assert_nothing_raised { Ses::ProcessEventJob.perform_now('[1, 2]') }
  end
end
