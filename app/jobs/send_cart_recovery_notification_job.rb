class SendCartRecoveryNotificationJob < ApplicationJob
  queue_as :default

  SKIP_REASON = 'canal da 1ª mensagem indisponível'.freeze

  def perform(abandoned_checkout_id, template, coupon_code, slot)
    checkout = AbandonedCheckout.find(abandoned_checkout_id)
    return if checkout.phone.blank?

    client = checkout.client
    campaign = client.campaigns.find_by(kind: :cart_recovery)
    first = slot.to_s == 'first'
    # 2ª mensagem (e reenvios) saem pelo mesmo canal da 1ª; sem ele, não enviamos por outro.
    channel_locked = !first || checkout.first_notified_at.present?
    return skip_unavailable_channel(checkout, first) if channel_locked && !same_channel?(checkout, client, campaign)

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

  private

  def same_channel?(checkout, client, campaign)
    current = client.whatsapp_evolution? ? 'evolution' : 'zapi'
    # Checkouts anteriores à Evolution foram todos enviados pela Z-API.
    return false unless (checkout.whatsapp_provider.presence || 'zapi') == current
    return true unless current == 'evolution'

    connection_id = checkout.whatsapp_connection_id
    connection_id.present? && campaign.present? && campaign.whatsapp_connections.exists?(id: connection_id)
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
