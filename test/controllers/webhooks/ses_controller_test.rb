require 'test_helper'
require_relative '../../support/sns_signer'

class Webhooks::SesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @signer = SnsSigner.new
    @previous_topic = ENV['SES_TOPIC_ARN']
    ENV['SES_TOPIC_ARN'] = SnsSigner::TOPIC
  end

  teardown { ENV['SES_TOPIC_ARN'] = @previous_topic }

  def deliver(data)
    Net::HTTP.stub(:get, @signer.certificate_pem) do
      post webhooks_ses_path, params: data.to_json, headers: { 'CONTENT_TYPE' => 'text/plain' }
    end
  end

  test 'a signed notification is accepted and processed in the background' do
    assert_enqueued_with(job: Ses::ProcessEventJob, args: ['{"eventType":"Delivery"}']) do
      deliver(@signer.notification('{"eventType":"Delivery"}'))
    end

    assert_response :ok
  end

  test 'a message with a bad signature is refused and nothing is processed' do
    data = @signer.notification('x').merge('Message' => 'adulterada')

    assert_no_enqueued_jobs { deliver(data) }
    assert_response :forbidden
  end

  test 'everything is refused while the topic is not configured' do
    ENV['SES_TOPIC_ARN'] = nil

    assert_no_enqueued_jobs { deliver(@signer.notification('x')) }
    assert_response :forbidden
  end

  test 'a subscription confirmation visits the SNS confirmation url' do
    Net::HTTP.stub(:get_response, Net::HTTPOK.new('1.1', '200', 'OK')) { deliver(@signer.confirmation) }

    assert_response :ok
  end

  test 'oversized bodies are refused' do
    post webhooks_ses_path, params: 'a' * (Webhooks::SesController::MAX_BYTES + 1), headers: { 'CONTENT_TYPE' => 'text/plain' }

    assert_response :payload_too_large
  end
end
