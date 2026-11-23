module CampaignsHelper
  STATUS_TAGS = { 'draft' => 'neutral', 'scheduled' => 'info', 'sending' => 'warning', 'paused' => 'warning',
                  'sent' => 'success', 'cancelled' => 'danger' }.freeze

  def campaign_status_tag(campaign)
    tag.span(campaign.status_label, class: "crm-tag crm-tag--#{STATUS_TAGS.fetch(campaign.status)}")
  end

  def campaign_cost_label(cost)
    return 'menos de R$ 0,01' if cost.positive? && cost < BigDecimal('0.01')

    number_to_currency(cost, unit: 'R$', separator: ',', delimiter: '.', format: '%u %n')
  end

  CHANNEL_ICONS = { 'email' => 'fa-solid fa-envelope', 'whatsapp' => 'fa-brands fa-whatsapp' }.freeze

  # "Receberam alguma mensagem" vira "Receberam algum WhatsApp" quando a tela "Quem recebeu" está filtrada por canal.
  def campaign_deliveries_filter_label(filter, channel)
    return Campaigns::Deliveries::FILTERS.fetch(filter) if channel.nil? || filter == 'todos'

    what = channel == 'whatsapp' ? 'WhatsApp' : 'e-mail'
    filter == 'receberam' ? "Receberam algum #{what}" : "Não receberam nenhum #{what}"
  end

  # Status de uma mensagem. Boas-vindas que já saiu e segue mandando para quem entra no segmento aparece como
  # "Boas-vindas ativa", e não "Agendada" (que confundia ao lado de "53 de 53 enviados").
  def campaign_message_status_tag(message)
    if message.started_at && message.runnable? && message.status != 'paused' && message.continuing?
      return tag.span('Boas-vindas ativa', class: 'crm-tag crm-tag--success')
    end

    tag.span(Campaign::STATUSES.fetch(message.status, message.status),
             class: "crm-tag crm-tag--#{STATUS_TAGS.fetch(message.status, 'neutral')}")
  end

  def campaign_channel_tag(channel)
    tag.span(class: "crm-tag crm-tag--#{channel == 'whatsapp' ? 'success' : 'info'}") do
      safe_join([tag.i(class: CHANNEL_ICONS.fetch(channel)), ' ', CampaignMessage::CHANNEL_LABELS.fetch(channel)])
    end
  end

  # Canais ligados; numa campanha já confirmada, os canais que de fato têm mensagens.
  def campaign_channels(campaign)
    used = campaign.messages.reject { |m| m.status == 'cancelled' }.map(&:channel).uniq
    campaign.draft? || used.empty? ? campaign.enabled_channels : CampaignMessage::CHANNELS & used
  end
end
