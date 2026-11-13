class SendCampaignNotificationJob < ApplicationJob
  queue_as :default

  def perform(campaign_action_id, extra = {})
    extra = extra.symbolize_keys
    action = CampaignAction.find(campaign_action_id)
    campaign = action.campaign
    customer = action.customer
    order = action.order

    phone = customer.default_address_phone.presence || customer.phone
    if phone.blank?
      action.mark_as_failed!('Cliente sem telefone cadastrado')
      return
    end

    message = build_message(campaign: campaign, customer: customer, order: order, extra: extra)

    result = Whatsapp::Outbound.deliver(client: campaign.client, campaign: campaign, phone: phone, body: message)

    if result.ok
      action.mark_as_sent!(message)
    else
      action.mark_as_failed!(result.error)
    end
  end

  private

  def build_message(campaign:, customer:, order:, extra:)
    name = [customer.first_name, customer.last_name].compact.join(' ').presence || customer.name.presence || 'cliente'

    campaign.message.to_s
            .gsub('{nome}', name)
            .gsub('{pedido}', order&.shopify_order_number.to_s)
            .gsub('{cupom}', extra[:code].to_s)
            .gsub('{desconto}', format_discount(extra[:discount_value]))
            .gsub('{expiracao}', extra[:ends_at]&.to_date&.strftime('%d/%m/%Y').to_s)
            .gsub('{rastreio}', order&.tracking_number.to_s)
            .gsub('{transportadora}', order&.tracking_company.to_s)
            .gsub('{link_rastreio}', order&.tracking_url.to_s)
  end

  def format_discount(value)
    return '' if value.blank?

    "#{value.to_s.sub(/\.0\z/, '')}%"
  end
end
