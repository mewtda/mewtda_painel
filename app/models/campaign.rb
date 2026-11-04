class Campaign < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  belongs_to :client
  has_many :campaign_actions, dependent: :destroy
  has_many :whatsapp_campaign_connections, class_name: 'Whatsapp::CampaignConnection', dependent: :destroy
  has_many :whatsapp_connections, through: :whatsapp_campaign_connections, source: :connection

  enum kind: {
    cashback: 0,
    cashback_expiration: 1,
    marketing_notification: 2,
    shipping_tracking: 3,
    cart_recovery: 4
  }

  validates :name, presence: true
  validates :kind, presence: true
  validates :message, presence: true
  validates :days_after_purchase, presence: true, numericality: { greater_than: 0 }, unless: -> {
    marketing_notification? || shipping_tracking? || cart_recovery?
  }
  validates :max_sends, presence: true, numericality: { greater_than: 0 }, if: :shipping_tracking?
  validates :interval_days, presence: true, numericality: { greater_than: 0 }, if: :shipping_tracking?
  validates :send_delay_minutes, presence: true, numericality: { greater_than: 0 }, if: :cart_recovery?
  # O cupom é criado manualmente na Shopify por fora — aqui só guarda o código
  # já pronto, não gera nada via API.
  validates :coupon_code, presence: true, if: -> { cart_recovery? && include_coupon? }
  validates :resend_message, presence: true, if: -> { cart_recovery? && resend_enabled? }
  validates :resend_delay_hours, presence: true, numericality: { greater_than: 0 },
                                 if: -> { cart_recovery? && resend_enabled? }
  validates :resend_coupon_code, presence: true,
                                 if: -> { cart_recovery? && resend_enabled? && resend_include_coupon? }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :end_date_after_start_date

  # Accessors para os filtros armazenados no campo jsonb :filters
  # Exemplo de estrutura:
  # { "inactive_days" => "30", "min_orders" => "2", "product_name" => "Camiseta", "maderite" => "1" }
  %w[inactive_days min_orders product_name maderite].each do |key|
    define_method(:"filter_#{key}")        { filters[key] }
    define_method(:"filter_#{key}=") { |v| self.filters = filters.merge(key => v.presence) }
  end

  def filter_maderite?
    filters['maderite'] == '1'
  end

  scope :active,   -> { where(active: true) }
  scope :running,  -> { active.where('start_date <= ? AND end_date >= ?', Date.current, Date.current) }

  def running?
    active? && start_date <= Date.current && end_date >= Date.current
  end

  def zapi_configured?
    client&.zapi_instance_id.present? &&
      client&.zapi_instance_token.present? &&
      client&.zapi_client_token.present?
  end

  def status
    return :inactive unless active?
    return :pending  if start_date > Date.current
    return :finished if end_date < Date.current

    :running
  end

  def kind_label
    case kind
    when 'cashback'               then 'Cashback'
    when 'cashback_expiration'    then 'Expiração de Cashback'
    when 'marketing_notification' then 'Notificação de Marketing'
    when 'shipping_tracking'      then 'Rastreio de Pedido'
    when 'cart_recovery'          then 'Recuperação de Carrinho'
    else kind
    end
  end

  def days_after_purchase_label
    return nil if marketing_notification? || shipping_tracking? || cart_recovery?

    cashback_expiration? ? 'dias antes da expiração' : 'dias após a compra'
  end

  def actions_count = campaign_actions.count
  def sent_count    = campaign_actions.sent.count
  def pending_count = campaign_actions.pending.count
  def failed_count  = campaign_actions.failed.count

  def filtered_customers
    return Customer.none unless marketing_notification?

    scope = Customer.joins(:orders).where(orders: { client_id: }).distinct

    scope = scope.inactive_days(filter_inactive_days.to_i) if filter_inactive_days.present?
    scope = scope.with_min_orders(filter_min_orders.to_i)  if filter_min_orders.present?
    scope = scope.bought_product(filter_product_name)      if filter_product_name.present?
    scope = scope.maderite                                 if filter_maderite?

    scope
  end

  private

  def end_date_after_start_date
    return if start_date.blank? || end_date.blank?

    errors.add(:end_date, 'deve ser posterior à data de início') if end_date < start_date
  end
end
