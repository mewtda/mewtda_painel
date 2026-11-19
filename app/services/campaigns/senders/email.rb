module Campaigns
  module Senders
    # Envia a mensagem de e-mail da campanha para um destinatário (SES), como sempre foi.
    # deliver devolve :sent, :failed, :blocked ou [:pause | :wait, Time] (para o lote sem marcar a pessoa).
    class Email
      def initialize(message)
        @message = message
        @campaign = message.campaign
        @client = @campaign.client
      end

      def channel = 'email'

      # Motivo para não enviar agora: [nota, próxima tentativa (nil = só quando a loja mexer)].
      def blocker
        return ['O e-mail desta mensagem foi excluído. Escolha outro e confirme de novo.', nil] unless template
        return ['O domínio de envio da loja ainda não foi verificado.', 1.hour.from_now] unless client.ses_domain_verified?

        nil
      end

      def address(profile) = profile.email.to_s.strip.downcase.presence

      def deliver(recipient)
        return recipient.update!(status: 'blocked') && :blocked if EmailSuppression.suppressed?(client, recipient.email)

        mail = mail_for(recipient)
        sent = Ses::SendEmailService.new(client).call(
          to: recipient.email, subject: mail.subject, html_body: mail.html, text_body: mail.text,
          unsubscribe_url: mail.unsubscribe_url,
          tags: { source: 'campaign', campaign_id: campaign.id, recipient_id: recipient.id }
        )
        return recipient.update!(status: 'sent', sent_at: Time.current) && :sent if sent
        return [:pause, message.resume_at] if Billing::Usage.new(client).limit_reached?('email')

        recipient.update!(status: 'failed', error: 'O envio não foi aceito')
        :failed
      rescue Aws::SESV2::Errors::TooManyRequestsException
        [:wait, Time.current + DispatchJob::BACKOFF]
      rescue Aws::Errors::ServiceError => e
        recipient.update!(status: 'failed', error: e.message.to_s.first(250))
        :failed
      end

      private

      attr_reader :message, :campaign, :client

      def template = message.email_template

      def mail_for(recipient)
        EmailTemplates::Message.new(
          template,
          variables: { nome: recipient.name.to_s.split.first.presence || 'cliente', loja: client.name },
          default_url:, logo_url:,
          unsubscribe_url: EmailSuppression.unsubscribe_url(client, recipient.email, template:)
        )
      end

      def default_url
        @default_url ||= client.storefront_url.then { |url| url.match?(%r{\Ahttps?://[^/]+\z}) ? url : BackInStockSetting::WIDGET_HOST }
      end

      def logo_url
        return unless client.logo.attached?

        Rails.application.routes.url_helpers.rails_blob_url(client.logo, host: BackInStockSetting::WIDGET_HOST)
      end
    end
  end
end
