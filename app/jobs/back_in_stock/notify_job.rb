module BackInStock
  class NotifyJob < ApplicationJob
    queue_as :default

    def perform(alert_id, snapshot)
      alert = BackInStockAlert.find_by(id: alert_id)
      alert&.with_lock { deliver(alert, snapshot) if alert.pending? }
    end

    private

    def deliver(alert, snapshot)
      return alert.unsubscribe! if EmailSuppression.suppressed?(alert.client, alert.email)

      template = alert.client.back_in_stock_setting&.email_template
      return unless template

      message = message_for(alert, template, snapshot)
      alert.update!(status: :notified, notified_at: Time.current) if send_email(alert, message)
    rescue Aws::Errors::ServiceError => e
      Rails.logger.error "[BackInStock::Notify] Alerta #{alert.id}: #{e.message}"
    end

    def send_email(alert, message)
      Ses::SendEmailService.new(alert.client).call(to: alert.email, subject: message.subject,
                                                   html_body: message.html, text_body: message.text,
                                                   unsubscribe_url: message.unsubscribe_url)
    end

    def message_for(alert, template, snapshot)
      EmailTemplates::Message.new(
        template,
        variables: { produto: snapshot['title'], variacao: snapshot['variant'], loja: alert.client.name },
        product: { title: snapshot['title'], variant: snapshot['variant'], image: snapshot['image'], url: alert.product_url },
        default_url: alert.product_url,
        logo_url: attachment_url(alert.client.logo),
        unsubscribe_url: EmailSuppression.unsubscribe_url(alert.client, alert.email, template:)
      )
    end

    def attachment_url(attachment)
      return unless attachment.attached?

      Rails.application.routes.url_helpers.rails_blob_url(attachment, host: BackInStockSetting::WIDGET_HOST)
    end
  end
end
