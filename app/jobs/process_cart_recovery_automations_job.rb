class ProcessCartRecoveryAutomationsJob < ApplicationJob
  queue_as :default

  # A 1ª mensagem só vai para checkouts recentes: evita disparar carrinhos
  # antigos quando a sincronização traz o histórico da Shopify.
  FIRST_MESSAGE_MAX_AGE = 24.hours

  def perform(client_id = nil)
    scope = client_id ? Client.where(id: client_id) : Client.where(active: true)

    scope.find_each do |client|
      process_client(client)
    rescue StandardError => e
      Rails.logger.error "[ProcessCartRecoveryAutomations] Erro no client #{client.id}: #{e.message}"
    end
  end

  private

  def process_client(client)
    automation = client.automations.running.find_by(kind: :cart_recovery)
    return unless automation&.whatsapp_template_id && client.whatsapp_ready?

    process_template_notifications(client, automation)
  end

  # API Oficial: o modelo aprovado escolhido na automação, só para checkouts das últimas 24h
  # e a partir da data de início da automação.
  def process_template_notifications(client, automation)
    client.abandoned_checkouts.pending_first_notification.find_each do |checkout|
      next unless allowed_by_test_mode?(automation, checkout)
      next if checkout.checkout_created_at.blank?
      next if checkout.checkout_created_at < FIRST_MESSAGE_MAX_AGE.ago
      next if checkout.checkout_created_at < automation.start_date.beginning_of_day
      next if checkout.checkout_created_at + automation.send_delay_minutes.minutes > Time.current

      SendCartRecoveryTemplateJob.perform_later(checkout.id)
    end
  end

  # Modo teste: com um número de teste preenchido, só esse telefone recebe.
  def allowed_by_test_mode?(automation, checkout)
    return true if automation.test_phone.blank?

    test = Whatsapp::Phone.normalize(automation.test_phone)
    test.present? && Whatsapp::Phone.normalize(checkout.phone) == test
  end
end
