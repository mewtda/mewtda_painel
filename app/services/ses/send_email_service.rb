module Ses
  class SendEmailService
    SENDER_NAME = 'naoresponda'.freeze

    def initialize(client, ses: Aws::SESV2::Client.new)
      @client = client
      @ses = ses
    end

    def call(to:, subject:, html_body:, text_body: nil)
      return false unless client.ses_domain_verified?

      ses.send_email(email_params(to, subject, html_body, text_body))
      true
    end

    private

    attr_reader :client, :ses

    def email_params(to, subject, html_body, text_body)
      {
        from_email_address: sender,
        destination: { to_addresses: [to] },
        content: { simple: { subject: { data: subject }, body: body_params(html_body, text_body) } }
      }
    end

    def body_params(html_body, text_body)
      { html: { data: html_body }, text: ({ data: text_body } if text_body) }.compact
    end

    def sender
      address = Mail::Address.new("#{SENDER_NAME}@#{client.email_sending_domain}")
      address.display_name = client.name
      address.encoded
    end
  end
end
