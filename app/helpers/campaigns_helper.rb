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
end
