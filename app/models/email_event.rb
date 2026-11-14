class EmailEvent < ApplicationRecord
  TYPES = %w[delivery bounce complaint open click reject].freeze
  SOURCES = %w[campaign back_in_stock].freeze

  belongs_to :client
  belongs_to :campaign, optional: true
  belongs_to :campaign_recipient, optional: true
  belongs_to :back_in_stock_alert, optional: true

  validates :event_type, inclusion: { in: TYPES }
  validates :source, inclusion: { in: SOURCES }
  validates :ses_message_id, :occurred_at, presence: true
end
