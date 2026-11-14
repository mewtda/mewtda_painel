require 'net/http'

module Ses
  class SnsMessage
    CERTIFICATE_HOST = /\Asns\.[a-z0-9-]+\.amazonaws\.com(\.cn)?\z/
    CONFIRMATION_FIELDS = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type].freeze
    SIGNED_FIELDS = {
      'Notification' => %w[Message MessageId Subject Timestamp TopicArn Type],
      'SubscriptionConfirmation' => CONFIRMATION_FIELDS,
      'UnsubscribeConfirmation' => CONFIRMATION_FIELDS
    }.freeze
    DIGESTS = { '1' => 'SHA1', '2' => 'SHA256' }.freeze

    def initialize(raw, topic_arn: ENV['SES_TOPIC_ARN'], certificate_fetcher: method(:download_certificate))
      @data = JSON.parse(raw)
      @topic_arn = topic_arn
      @certificate_fetcher = certificate_fetcher
    rescue JSON::ParserError
      @data = nil
    end

    def valid?
      data.is_a?(Hash) && topic_arn.present? && data['TopicArn'] == topic_arn && SIGNED_FIELDS.key?(type) && signature_valid?
    end

    def type = data['Type']
    def message = data['Message']
    def notification? = type == 'Notification'
    def confirmation? = type == 'SubscriptionConfirmation'

    def confirm!
      uri = URI.parse(data['SubscribeURL'].to_s)
      return false unless trusted_uri?(uri)

      Net::HTTP.get_response(uri).is_a?(Net::HTTPSuccess)
    end

    private

    attr_reader :data, :topic_arn, :certificate_fetcher

    def signature_valid?
      digest = DIGESTS[data['SignatureVersion']]
      certificate = certificate_for(data['SigningCertURL'])
      return false unless digest && certificate

      certificate.public_key.verify(OpenSSL::Digest.new(digest), Base64.decode64(data['Signature'].to_s), string_to_sign)
    rescue OpenSSL::OpenSSLError, ArgumentError
      false
    end

    def string_to_sign
      SIGNED_FIELDS.fetch(type).filter_map { |field| "#{field}\n#{data[field]}\n" if data.key?(field) }.join
    end

    def certificate_for(url)
      uri = URI.parse(url.to_s)
      return unless trusted_uri?(uri) && uri.path.end_with?('.pem')

      OpenSSL::X509::Certificate.new(Rails.cache.fetch("sns_certificate/#{uri}", expires_in: 1.day) { certificate_fetcher.call(uri) })
    rescue URI::InvalidURIError, OpenSSL::OpenSSLError, SocketError, Timeout::Error
      nil
    end

    def trusted_uri?(uri)
      uri.is_a?(URI::HTTPS) && uri.host.to_s.match?(CERTIFICATE_HOST)
    end

    def download_certificate(uri)
      Net::HTTP.get(uri)
    end
  end
end
