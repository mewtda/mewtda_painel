class SendCartRecoveryNotificationJob < ApplicationJob
  queue_as :default

  SKIP_REASON = 'canal da 1ª mensagem indisponível'.freeze

  # Verdadeiro quando o reenvio/2ª mensagem ainda pode sair pelo canal da 1ª.
  def self.channel_available?(checkout, client, campaign)
    current = client.whatsapp_evolution? ? 'evolution' : 'zapi'
    # Checkouts anteriores à Evolution foram todos enviados pela Z-API.
    return false unless (checkout.whatsapp_provider.presence || 'zapi') == current
    return true unless current == 'evolution'

    connection_id = checkout.whatsapp_connection_id
    connection_id.present? && campaign.present? && campaign.whatsapp_connections.exists?(id: connection_id)
  end

  # 2ª mensagem (e reenvios) saem pelo mesmo canal da 1ª.
  def self.channel_locked?(checkout, slot)
    slot.to_s != 'first' || checkout.first_notified_at.present?
  end

  # manual: reenvio pedido pelo painel; os automáticos são idempotentes por etapa.
  def perform(abandoned_checkout_id, template, coupon_code, slot, manual = false)
    checkout = AbandonedCheckout.find(abandoned_checkout_id)
    return if checkout.phone.blank?

    checkout.with_lock do
      deliver(checkout, template, coupon_code, slot, manual)
    end
  end

  private

  def deliver(checkout, template, coupon_code, slot, manual)
    first = slot.to_s == 'first'
    return if !manual && (first ? checkout.first_notified_at : checkout.second_notified_at).present?

    client = checkout.client
    campaign = client.campaigns.find_by(kind: :cart_recovery)
    channel_locked = self.class.channel_locked?(checkout, slot)
    if channel_locked && !self.class.channel_available?(checkout, client, campaign)
      return skip_unavailable_channel(checkout, first)
    end

    message = build_message(template, checkout, coupon_code)
    result = Whatsapp::Outbound.deliver(client: client, campaign: campaign, phone: checkout.phone, body: message,
                                        prefer_connection: channel_locked ? checkout.whatsapp_connection : nil,
                                        strict: channel_locked)
    # Evolution sem número disponível: mantém o checkout pendente para tentar de novo.
    return if !result.ok && result.provider == 'evolution'

    sent = result.ok ? message : nil
    if first
      attrs = { first_notified_at: Time.current, first_message_sent: sent, first_coupon_code: coupon_code }
      attrs.merge!(channel_attributes(result)) unless channel_locked
      checkout.update!(attrs)
    else
      checkout.update!(second_notified_at: Time.current, second_message_sent: sent, second_coupon_code: coupon_code,
                       skip_reason: nil)
    end
  end

  def skip_unavailable_channel(checkout, first)
    return if first # reenvio da 1ª: nada a registrar

    checkout.update!(second_notified_at: Time.current, skip_reason: SKIP_REASON)
  end

  def channel_attributes(result)
    { whatsapp_provider: result.provider, whatsapp_connection_id: result.connection&.id,
      whatsapp_conversation_id: result.message&.conversation_id }
  end

  def build_message(template, checkout, coupon_code)
    name = checkout.customer&.name.presence || 'cliente'

    template.to_s
            .gsub('{nome}', name)
            .gsub('{cupom}', coupon_code.to_s)
            .gsub('{link}', checkout.recovery_url.to_s)
  end
end
