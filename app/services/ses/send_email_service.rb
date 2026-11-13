module Ses
  class SendEmailService
    SENDER_NAME = 'naoresponda'.freeze

    def initialize(client, ses: Aws::SESV2::Client.new)
      @client = client
      @ses = ses
    end

    # Retorna false (sem enviar) quando o domínio não está verificado, quando o
    # destinatário está na lista de recusa da loja ou quando o limite diário de
    # e-mails do cliente já foi atingido. Cada envio conta no uso do dia.
    def call(to:, subject:, html_body:, text_body: nil, unsubscribe_url: nil)
      return false unless client.ses_domain_verified?
      return false if EmailSuppression.suppressed?(client, to)
      return false if Billing::Usage.new(client).limit_reached?('email')

      ses.send_email(email_params(to, subject, html_body, text_body, unsubscribe_url))
      MessageUsage.track!(client, 'email')
      true
    end

    private

    attr_reader :client, :ses

    def email_params(to, subject, html_body, text_body, unsubscribe_url)
      simple = { subject: { data: subject }, body: body_params(html_body, text_body) }
      simple[:headers] = unsubscribe_headers(unsubscribe_url) if unsubscribe_url

      { from_email_address: sender, destination: { to_addresses: [to] }, content: { simple: } }
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
      address = Mail::Address.new("#{SENDER_NAME}@#{client.email_sending_domain}")
      address.display_name = client.name
      address.encoded
    end
  end
end
