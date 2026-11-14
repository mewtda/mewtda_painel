require 'test_helper'
require_relative '../../support/sns_signer'

class Ses::SnsMessageTest < ActiveSupport::TestCase
  setup do
    @signer = SnsSigner.new
    @fetcher = ->(_uri) { @signer.certificate_pem }
  end

  def sns_for(data, topic: SnsSigner::TOPIC) = Ses::SnsMessage.new(data.to_json, topic_arn: topic, certificate_fetcher: @fetcher)

  test 'accepts a notification signed by the trusted certificate' do
    sns = sns_for(@signer.notification('{"eventType":"Delivery"}'))

    assert sns.valid?
    assert sns.notification?
    assert_equal '{"eventType":"Delivery"}', sns.message
  end

  test 'rejects a message whose content was changed after signing' do
    data = @signer.notification('original').merge('Message' => 'adulterada')

    assert_not sns_for(data).valid?
  end

  test 'rejects another topic and an unconfigured topic' do
    data = @signer.notification('x')

    assert_not sns_for(data, topic: 'arn:aws:sns:us-east-1:999999999999:outro').valid?
    assert_not sns_for(data, topic: nil).valid?
  end

  test 'rejects certificates that are not hosted by SNS' do
    data = @signer.notification('x').merge('SigningCertURL' => 'https://evil.example.com/cert.pem')

    assert_not sns_for(data).valid?
  end

  test 'rejects a signature made by another key' do
    forged = SnsSigner.new.notification('x')

    assert_not sns_for(forged).valid?
  end

  test 'rejects invalid JSON and unknown message types' do
    assert_not Ses::SnsMessage.new('não é json', topic_arn: SnsSigner::TOPIC).valid?
    assert_not sns_for(@signer.notification('x').merge('Type' => 'Other')).valid?
  end

  test 'confirms the subscription only through a trusted SNS url' do
    sns = sns_for(@signer.confirmation)

    assert sns.valid?
    assert sns.confirmation?
    Net::HTTP.stub(:get_response, Net::HTTPOK.new('1.1', '200', 'OK')) { assert sns.confirm! }

    forged = sns_for(@signer.confirmation.merge('SubscribeURL' => 'https://evil.example.com/confirm'))
    assert_not forged.confirm!
  end
end
