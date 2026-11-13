class Customer < ApplicationRecord
  has_many :orders, dependent: :nullify
  has_many :campaign_actions, dependent: :nullify
  has_many :customer_profiles, dependent: :delete_all
  has_many :segment_memberships, dependent: :delete_all

  validates :shopify_customer_id, uniqueness: true

  scope :search, lambda { |term|
    where(
      'customers.first_name ILIKE :q OR customers.last_name ILIKE :q OR customers.email ILIKE :q',
      q: "%#{term}%"
    )
  }

  scope :phone_like, lambda { |phone|
    where('customers.phone ILIKE ?', "%#{phone}%")
  }

  scope :with_min_orders, lambda { |min|
    joins(:orders)
      .group('customers.id')
      .having('COUNT(orders.id) >= ?', min)
  }

  scope :inactive_days, lambda { |days|
    cutoff = days.to_i.days.ago
    where.not(
      id: Order.where('created_at >= ?', cutoff).select(:customer_id)
    )
  }

  scope :bought_product, lambda { |product_name|
    joins(orders: :order_items)
      .joins('JOIN products ON products.id = order_items.product_id')
      .where('products.shopify_product_name ILIKE ?', "%#{product_name}%")
      .distinct
  }

  scope :maderite, lambda {
    joins(orders: :order_items)
      .joins('JOIN products ON products.id = order_items.product_id')
      .where('products.tags ILIKE ?', '%maderite%')
      .distinct
  }

  scope :with_orders_count, lambda {
    left_joins(:orders)
      .select('customers.*, COUNT(orders.id) AS orders_count')
      .group('customers.id')
  }

  def full_name
    [first_name, last_name].compact.join(' ').presence || 'Sem nome'
  end
end
