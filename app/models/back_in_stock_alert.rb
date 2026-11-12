class BackInStockAlert < ApplicationRecord
  PENDING_LIMIT_PER_EMAIL = 20
  TRENDING_WINDOW = 7.days
  SORTS = {
    'demand' => ['alerts_count DESC'],
    'value' => ['demand_value DESC', 'alerts_count DESC'],
    'trending' => ['recent_count DESC', 'alerts_count DESC']
  }.freeze

  belongs_to :client

  enum :status, { pending: 'pending', notified: 'notified', cancelled: 'cancelled' }, default: :pending

  attribute :consented_at, default: -> { Time.current }

  generates_token_for :unsubscribe

  before_save :stamp_cancelled_at, if: -> { cancelled? && cancelled_at.nil? }

  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :phone, with: ->(phone) { Whatsapp::Phone.normalize(phone) }

  validates :shopify_product_id, :shopify_variant_id, presence: true
  validates :product_handle, format: { with: /\A[a-z0-9-]+\z/ }, length: { maximum: 255 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }
  validates :product_title, :variant_title, :sku, length: { maximum: 255 }
  validates :image_url, format: { with: %r{\Ahttps://} }, length: { maximum: 1000 }, allow_blank: true
  validate :pending_limit_per_email, on: :create

  scope :search, lambda { |term|
    next if term.blank?

    where('product_title ILIKE :term OR sku ILIKE :term OR email ILIKE :term', term: "%#{sanitize_sql_like(term)}%")
  }

  def self.register(attributes)
    pending.create_or_find_by(attributes.slice(:shopify_variant_id, :email)) do |alert|
      alert.assign_attributes(attributes)
    end
  end

  def self.grouped_by_variant(sort)
    group(:shopify_variant_id)
      .select(:shopify_variant_id,
              'MAX(product_handle) AS product_handle',
              'MAX(product_title) AS product_title',
              'MAX(variant_title) AS variant_title',
              'MAX(sku) AS sku',
              'MAX(image_url) AS image_url',
              'MAX(price) AS price',
              'COUNT(*) AS alerts_count',
              'COALESCE(MAX(price), 0) * COUNT(*) AS demand_value',
              sanitize_sql_array(['COUNT(*) FILTER (WHERE created_at >= ?) AS recent_count', TRENDING_WINDOW.ago]),
              'MIN(created_at) AS first_requested_at',
              'MAX(created_at) AS last_requested_at')
      .order(*SORTS.fetch(sort), :shopify_variant_id)
  end

  def self.contacts_by_variant
    select(:id, :shopify_variant_id, :email, :phone, :created_at, :notified_at, :cancelled_at)
      .order(created_at: :desc)
      .group_by(&:shopify_variant_id)
  end

  def self.notified_by_month(since)
    month = sanitize_sql_array(["DATE_TRUNC('month', notified_at AT TIME ZONE 'UTC' AT TIME ZONE ?)", Time.zone.tzinfo.name])
    notified.where(notified_at: since..).group(month).count.transform_keys(&:to_date)
  end

  def product_url
    "#{client.storefront_url}/products/#{product_handle}?variant=#{shopify_variant_id}"
  end

  def unsubscribe_url
    path = Rails.application.routes.url_helpers.widget_back_in_stock_unsubscribe_path(token: generate_token_for(:unsubscribe))
    "#{BackInStockSetting::WIDGET_HOST}#{path}"
  end

  def unsubscribe!
    cancelled! if pending?
  end

  private

  def stamp_cancelled_at
    self.cancelled_at = Time.current
  end

  def pending_limit_per_email
    return if client.back_in_stock_alerts.pending.where(email:).count < PENDING_LIMIT_PER_EMAIL

    errors.add(:base, 'Limite de alertas atingido para este e-mail.')
  end
end
