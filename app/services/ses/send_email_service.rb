module Ses
  class SendEmailService
    SENDER_NAME = 'naoresponda'.freeze

    def initialize(client, ses: Aws::SESV2::Client.new, shared: false)
      @client = client
      @ses = ses
      @shared = shared
    end

    # Retorna false (sem enviar) quando o domínio não está verificado, quando o
    # destinatário está na lista de recusa da loja ou quando o limite diário de
    # e-mails do cliente já foi atingido. Cada envio conta no uso do dia.
    def call(to:, subject:, html_body:, text_body: nil, unsubscribe_url: nil, tags: {})
      return false unless domain
      return false if EmailSuppression.suppressed?(client, to)
      return false if Billing::Usage.new(client).limit_reached?('email')

      ses.send_email(email_params(to, subject, html_body, text_body, unsubscribe_url, tags))
      MessageUsage.track!(client, 'email')
      true
    end

    private

    attr_reader :client, :ses

    def domain = @shared ? client.tools_email_domain : (client.email_sending_domain if client.ses_domain_verified?)

    def email_params(to, subject, html_body, text_body, unsubscribe_url, tags)
      simple = { subject: { data: subject }, body: body_params(html_body, text_body) }
      simple[:headers] = unsubscribe_headers(unsubscribe_url) if unsubscribe_url

      { from_email_address: sender, destination: { to_addresses: [to] }, content: { simple: } }.merge(tracking_params(tags))
    end

    def tracking_params(tags)
      configuration_set = ENV['SES_CONFIGURATION_SET'].presence
      return {} unless configuration_set && tags.present?

      { configuration_set_name: configuration_set,
        email_tags: tags.merge(client_id: client.id).map { |name, value| { name: name.to_s, value: value.to_s } } }
    end

    # Permite o botão "Cancelar inscrição" nativo do Gmail/Outlook (RFC 8058).
    def unsubscribe_headers(url)
      [
        { name: 'List-Unsubscribe', value: "<#{url}>" },
        { name: 'List-Unsubscribe-Post', value: 'List-Unsubscribe=One-Click' }
      ]
    end

    def body_params(html_body, text_body)
      { html: { data: html_body }, text: ({ data: text_body } if text_body) }.compact
    end

    def sender
      address = Mail::Address.new("#{SENDER_NAME}@#{domain}")
      address.display_name = client.name
      address.encoded
    end
  end
end
