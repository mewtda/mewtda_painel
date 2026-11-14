class SnsSigner
  CERT_URL = 'https://sns.us-east-1.amazonaws.com/SimpleNotificationService.pem'.freeze
  TOPIC = 'arn:aws:sns:us-east-1:111122223333:mewtda-ses-eventos'.freeze

  attr_reader :certificate_pem

  def initialize
    @key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse('/CN=sns.test')
    certificate.public_key = @key.public_key
    certificate.not_before = 1.day.ago
    certificate.not_after = 1.year.from_now
    certificate.sign(@key, OpenSSL::Digest.new('SHA256'))
    @certificate_pem = certificate.to_pem
  end

  def notification(message, topic: TOPIC)
    sign('Type' => 'Notification', 'MessageId' => SecureRandom.uuid, 'TopicArn' => topic, 'Message' => message,
         'Timestamp' => Time.current.iso8601)
  end

  def confirmation(topic: TOPIC)
    sign('Type' => 'SubscriptionConfirmation', 'MessageId' => SecureRandom.uuid, 'TopicArn' => topic, 'Message' => 'confirme',
         'Timestamp' => Time.current.iso8601, 'Token' => 'abc123',
         'SubscribeURL' => 'https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=abc123')
  end

  private

  def sign(data)
    fields = Ses::SnsMessage::SIGNED_FIELDS.fetch(data['Type'])
    string = fields.filter_map { |field| "#{field}\n#{data[field]}\n" if data.key?(field) }.join
    data.merge('SignatureVersion' => '2', 'SigningCertURL' => CERT_URL,
               'Signature' => Base64.strict_encode64(@key.sign(OpenSSL::Digest.new('SHA256'), string)))
  end
end
