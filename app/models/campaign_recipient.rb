class CampaignRecipient < ApplicationRecord
  STATUSES = %w[pending sent failed blocked].freeze

  belongs_to :campaign
  belongs_to :customer, optional: true

  validates :email, presence: true
  validates :status, inclusion: { in: STATUSES }
end
