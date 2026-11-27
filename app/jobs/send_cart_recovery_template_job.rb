# Envia a 1ª mensagem da recuperação de carrinho como modelo aprovado da API Oficial (Cloud API).
# {{1}} do corpo = primeiro nome (ou "cliente"); a variável do botão de link = slug do checkout, que
# abre /carrinho/:slug no painel e redireciona para o checkout da loja com o cupom aplicado.
#
# Falha temporária (Meta fora, limite de envio, conta pausada, modelo fora do ar) deixa o checkout pendente
# para a próxima rodada; recusa da pessoa (bloqueio, número inválido) marca como enviado com o motivo.
class SendCartRecoveryTemplateJob < ApplicationJob
  queue_as :default

  def perform(abandoned_checkout_id, manual = false)
    checkout = AbandonedCheckout.find_by(id: abandoned_checkout_id)
    return if checkout.nil? || checkout.phone.blank?

    checkout.with_lock { deliver(checkout, manual) }
  end

  private

  def deliver(checkout, manual)
    return if !manual && checkout.first_notified_at.present?

    client = checkout.client
    automation = client.automations.find_by(kind: :cart_recovery)
    template = automation&.whatsapp_template
    return unless template&.approved?
    return if Billing::Usage.new(client).limit_reached?('whatsapp')

    coupon_code = automation.include_coupon? ? automation.coupon_code.presence : nil
    # O cupom vai antes do envio: o link do botão já pode ser aberto assim que a mensagem chega.
    checkout.update!(first_coupon_code: coupon_code)
    first_name = first_name_for(checkout)

    message_id = Whatsapp::Cloud::Api.new(client).send_template(
      to: checkout.phone, name: template.name, language: template.language,
      body_params: template.uses_variable? ? [first_name] : [],
      url_button_param: (checkout.slug if template.button_url.to_s.include?(WhatsappTemplate::VARIABLE))
    )
    checkout.update!(first_notified_at: Time.current, first_message_sent: template.preview_body(first_name),
                     whatsapp_provider: 'cloud', skip_reason: nil, whatsapp_message_id: message_id,
                     whatsapp_status: 'sent', whatsapp_status_at: Time.current, whatsapp_error: nil)
  rescue Whatsapp::Cloud::Api::Blocked => e
    mark_failed(checkout, e)
  rescue Whatsapp::Cloud::Api::RateLimited, Whatsapp::Cloud::Api::Paused, Whatsapp::Cloud::Api::NotConfigured => e
    Rails.logger.warn "[SendCartRecoveryTemplate] checkout #{checkout.id} adiado: #{e.message}"
  rescue Whatsapp::Cloud::Api::Error => e
    # Sem código = a Meta não respondeu: tenta de novo na próxima rodada.
    return Rails.logger.warn("[SendCartRecoveryTemplate] checkout #{checkout.id} sem resposta da Meta") if e.code.nil?

    mark_failed(checkout, e)
  end

  # Cliente vinculado ou o nome guardado no checkout; "cliente" quando não há nenhum.
  def first_name_for(checkout)
    name = checkout.customer&.first_name.presence || checkout.customer&.name.presence || checkout.customer_name
    name.to_s.split.first&.capitalize || 'cliente'
  end

  def mark_failed(checkout, error)
    checkout.update!(first_notified_at: Time.current, whatsapp_provider: 'cloud',
                     skip_reason: "API Oficial: #{error.message}".first(250))
  end
end
