module Whatsapp
  # Número responsável por uma automação; as mensagens da automação alternam entre eles.
  class CampaignConnection < ApplicationRecord
    self.table_name = 'whatsapp_campaign_connections'

    belongs_to :campaign
    belongs_to :connection, class_name: 'Whatsapp::Connection'
    validates :connection_id, uniqueness: { scope: :campaign_id }
    validate do
      errors.add(:connection, 'número de outro cliente') if campaign && connection && connection.client_id != campaign.client_id
    end

    after_create do
      campaign.update!(evolution_started_at: Time.current) if campaign.evolution_started_at.nil?
    end
  end
end
