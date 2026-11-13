class ProcessCartRecoveryCampaignsJob < ApplicationJob
  queue_as :default

  # A 1ª mensagem só vai para checkouts recentes: evita disparar carrinhos
  # antigos quando a sincronização traz o histórico da Shopify.
  FIRST_MESSAGE_MAX_AGE = 24.hours

  def perform(client_id = nil)
    scope = client_id ? Client.where(id: client_id) : Client.where(active: true)

    scope.find_each do |client|
      process_client(client)
    rescue StandardError => e
      Rails.logger.error "[ProcessCartRecoveryCampaigns] Erro no client #{client.id}: #{e.message}"
    end
  end

  private

  def process_client(client)
    campaign = client.campaigns.running.find_by(kind: :cart_recovery)
    return unless campaign
    return unless client.whatsapp_ready?

    process_first_notifications(client, campaign)
    process_resend_notifications(client, campaign) if campaign.resend_enabled?
  end

  def process_first_notifications(client, campaign)
    # Na Evolution só entram checkouts criados depois do primeiro número vinculado à automação.
    evolution_since = campaign.evolution_started_at
    return if client.whatsapp_evolution? && evolution_since.nil?

    client.abandoned_checkouts.pending_first_notification.find_each do |checkout|
      next unless allowed_by_test_mode?(campaign, checkout)
      next if checkout.checkout_created_at.blank?
      next if checkout.checkout_created_at < FIRST_MESSAGE_MAX_AGE.ago
      next if client.whatsapp_evolution? && checkout.checkout_created_at < evolution_since
      next if checkout.checkout_created_at + campaign.send_delay_minutes.minutes > Time.current

      coupon_code = campaign.include_coupon? ? campaign.coupon_code : nil
      SendCartRecoveryNotificationJob.perform_later(checkout.id, campaign.message, coupon_code, 'first')
    end
  end

  def process_resend_notifications(client, campaign)
    client.abandoned_checkouts.pending_second_notification.find_each do |checkout|
      next unless allowed_by_test_mode?(campaign, checkout)
      next if checkout.first_notified_at + campaign.resend_delay_hours.hours > Time.current

      coupon_code = campaign.resend_include_coupon? ? campaign.resend_coupon_code : nil
      SendCartRecoveryNotificationJob.perform_later(checkout.id, campaign.resend_message, coupon_code, 'second')
    end
  end

  # Modo teste: com um número de teste preenchido, só esse telefone recebe.
  def allowed_by_test_mode?(campaign, checkout)
    return true if campaign.test_phone.blank?

    test = Whatsapp::Phone.normalize(campaign.test_phone)
    test.present? && Whatsapp::Phone.normalize(checkout.phone) == test
  end
end
