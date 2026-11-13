class CampaignAction < ApplicationRecord
  extend FriendlyId
  friendly_id :random_slug, use: :slugged

  belongs_to :campaign
  belongs_to :customer
  belongs_to :order, optional: true

  enum kind: {
    cashback: 0,
    cashback_expiration: 1,
    marketing_notification: 2,
    shipping_tracking: 3
  }

  enum status: {
    pending: 0,
    sent: 1,
    delivered: 2,
    failed: 3,
    cancelled: 4
  }

  validates :kind, presence: true
  validates :status, presence: true

  scope :notified, -> { where.not(notified_at: nil) }
  scope :not_notified, -> { where(notified_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def notified?
    notified_at.present?
  end

  def mark_as_sent!(message = nil)
    update!(
      status: :sent,
      notified_at: Time.current,
      message_sent: message || self.message_sent
    )
  end

  def mark_as_delivered!
    update!(status: :delivered)
  end

  def mark_as_failed!(error = nil)
    update!(
      status: :failed,
      error_message: error
    )
  end

  private

  # Sem um campo "nome" natural — gera um slug opaco só na criação
  # (FriendlyId só chama isso quando o slug ainda está em branco).
  def random_slug
    SecureRandom.hex(6)
  end
end
