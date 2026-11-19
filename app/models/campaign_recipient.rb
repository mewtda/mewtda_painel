class CampaignRecipient < ApplicationRecord
  STATUSES = %w[pending sent failed blocked].freeze

  belongs_to :campaign
  belongs_to :message, class_name: 'CampaignMessage', foreign_key: :campaign_message_id, optional: true,
                       inverse_of: :recipients
  belongs_to :customer, optional: true

  validates :email, presence: true, if: -> { channel == 'email' }
  validates :phone, presence: true, if: -> { channel == 'whatsapp' }
  validates :channel, inclusion: { in: CampaignMessage::CHANNELS }
  validates :status, inclusion: { in: STATUSES }
end
