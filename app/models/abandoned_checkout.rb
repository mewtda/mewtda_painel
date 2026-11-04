class AbandonedCheckout < ApplicationRecord
  extend FriendlyId
  friendly_id :random_slug, use: :slugged

  belongs_to :client
  belongs_to :customer, optional: true
  belongs_to :whatsapp_connection, class_name: 'Whatsapp::Connection', optional: true
  belongs_to :whatsapp_conversation, class_name: 'Whatsapp::Conversation', optional: true

  scope :recent, -> { order(checkout_created_at: :desc) }
  scope :with_phone, -> { where.not(phone: [nil, '']) }
  scope :not_recovered, -> { where(completed_at: nil) }
  scope :pending_first_notification, -> { not_recovered.with_phone.where(first_notified_at: nil) }
  scope :pending_second_notification, -> {
    not_recovered.with_phone.where.not(first_notified_at: nil).where(second_notified_at: nil)
  }

  def recovered?
    completed_at.present?
  end

  def status
    return :recovered if recovered?
    return :skipped if skip_reason.present?
    return :second_sent if second_notified_at.present?
    return :first_sent if first_notified_at.present?

    :pending
  end

  private

  def random_slug
    SecureRandom.hex(6)
  end
end
