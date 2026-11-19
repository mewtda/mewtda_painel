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
