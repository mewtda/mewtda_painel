class Order < ApplicationRecord
  belongs_to :customer, optional: true
  belongs_to :client
  belongs_to :location, optional: true
  belongs_to :landing_page, optional: true
  has_many :order_items, dependent: :destroy
  has_many :automation_actions, dependent: :nullify

  # Escopos de busca
  scope :by_number, lambda { |q| where('shopify_order_number ILIKE ?', "%#{q}%") if q.present? }
  scope :by_kinds,  lambda { |k| where(kinds: k) if k.present? }
  scope :by_staff,  lambda { |s| where('staff_name ILIKE ?', "%#{s}%") if s.present? }
  scope :by_date_from, lambda { |d| where('shopify_creation_date >= ?', d.to_date.beginning_of_day) if d.present? }
  scope :by_date_to,   lambda { |d| where('shopify_creation_date <= ?', d.to_date.end_of_day) if d.present? }
  scope :not_cancelled, -> { where(cancelled_at: nil) }
  # Tags que representam a mesma vendedora: escolher qualquer uma na meta soma
  # os pedidos de todas as do grupo.
  TAG_GROUPS = [%w[VendedoraElo Eloina]].freeze

  # Aceita várias tags separadas por vírgula ("VendedoraElo, Eloina"): o
  # pedido entra se tiver qualquer uma delas.
  scope :with_any_tag, lambda { |value|
    tags = value.to_s.split(',').map(&:strip).reject(&:blank?)
    next all if tags.empty?

    tags = tags.flat_map { |t| TAG_GROUPS.find { |g| g.any? { |a| a.casecmp?(t) } } || [t] }.uniq(&:downcase)

    where(Array.new(tags.size, 'tags ILIKE ?').join(' OR '), *tags.map { |t| "%#{sanitize_sql_like(t)}%" })
  }

  # Helpers
  def total
    order_items.sum { |i| i.price.to_f * i.quantity.to_i }
  end

  def paid_total
    total_price || total
  end

  def customer_name
    customer&.full_name.presence || 'Sem cliente'
  end

  def customer_phone
    customer&.phone.to_s
  end
end
