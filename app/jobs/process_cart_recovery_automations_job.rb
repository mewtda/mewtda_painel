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
    return unless automation
    return unless client.whatsapp_ready?

    process_first_notifications(client, automation)
    process_resend_notifications(client, automation) if automation.resend_enabled?
  end

  def process_first_notifications(client, automation)
    # Na Evolution só entram checkouts criados depois do primeiro número vinculado à automação.
    evolution_since = automation.evolution_started_at
    return if client.whatsapp_evolution? && evolution_since.nil?

    client.abandoned_checkouts.pending_first_notification.find_each do |checkout|
      next unless allowed_by_test_mode?(automation, checkout)
      next if checkout.checkout_created_at.blank?
      next if checkout.checkout_created_at < FIRST_MESSAGE_MAX_AGE.ago
      next if client.whatsapp_evolution? && checkout.checkout_created_at < evolution_since
      next if checkout.checkout_created_at + automation.send_delay_minutes.minutes > Time.current

      coupon_code = automation.include_coupon? ? automation.coupon_code : nil
      SendCartRecoveryNotificationJob.perform_later(checkout.id, automation.message, coupon_code, 'first')
    end
  end

  def process_resend_notifications(client, automation)
    client.abandoned_checkouts.pending_second_notification.find_each do |checkout|
      next unless allowed_by_test_mode?(automation, checkout)
      next if checkout.first_notified_at + automation.resend_delay_hours.hours > Time.current

      coupon_code = automation.resend_include_coupon? ? automation.resend_coupon_code : nil
      SendCartRecoveryNotificationJob.perform_later(checkout.id, automation.resend_message, coupon_code, 'second')
    end
  end

  # Modo teste: com um número de teste preenchido, só esse telefone recebe.
  def allowed_by_test_mode?(automation, checkout)
    return true if automation.test_phone.blank?

    test = Whatsapp::Phone.normalize(automation.test_phone)
    test.present? && Whatsapp::Phone.normalize(checkout.phone) == test
  end
end
