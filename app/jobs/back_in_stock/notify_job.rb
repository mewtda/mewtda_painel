module BackInStock
  class NotifyJob < ApplicationJob
    queue_as :default

    def perform(alert_id, snapshot)
      alert = BackInStockAlert.find_by(id: alert_id)
      alert&.with_lock { deliver(alert, snapshot) if alert.pending? }
    end

    private

    def deliver(alert, snapshot)
      template = alert.client.back_in_stock_setting&.email_template
      return unless template

      message = message_for(alert, template, snapshot)
      alert.update!(status: :notified, notified_at: Time.current) if send_email(alert, message)
    rescue Aws::Errors::ServiceError => e
      Rails.logger.error "[BackInStock::Notify] Alerta #{alert.id}: #{e.message}"
    end

    def send_email(alert, message)
      Ses::SendEmailService.new(alert.client).call(to: alert.email, subject: message.subject,
                                                   html_body: message.html, text_body: message.text)
    end

    def message_for(alert, template, snapshot)
      EmailTemplates::Message.new(
        template,
        variables: { produto: snapshot['title'], variacao: snapshot['variant'], loja: alert.client.name },
        product: { title: snapshot['title'], variant: snapshot['variant'] },
        image_url: snapshot['image'],
        image_bottom_url: attachment_url(template.image_bottom),
        logo_url: attachment_url(alert.client.logo),
        button_url: alert.product_url,
        unsubscribe_url: alert.unsubscribe_url
      )
    end

    def attachment_url(attachment)
      return unless attachment.attached?

      Rails.application.routes.url_helpers.rails_blob_url(attachment, host: BackInStockSetting::WIDGET_HOST)
    end
  end
end
