class Automation < ApplicationRecord
  extend FriendlyId
  friendly_id :name, use: :slugged

  belongs_to :client
  # Recuperação de carrinho pela API Oficial: a mensagem sai como o modelo aprovado escolhido aqui.
  belongs_to :whatsapp_template, optional: true
  has_many :automation_actions, dependent: :destroy

  enum kind: {
    cashback: 0,
    cashback_expiration: 1,
    marketing_notification: 2,
    shipping_tracking: 3,
    cart_recovery: 4
  }

  validates :name, presence: true
  validates :kind, presence: true
  validates :message, presence: true, unless: :cart_recovery?
  validates :days_after_purchase, presence: true, numericality: { greater_than: 0 }, unless: -> {
    marketing_notification? || shipping_tracking? || cart_recovery?
  }
  validates :max_sends, presence: true, numericality: { greater_than: 0 }, if: :shipping_tracking?
  validates :interval_days, presence: true, numericality: { greater_than: 0 }, if: :shipping_tracking?
  validates :send_delay_minutes, presence: true, numericality: { greater_than: 0 }, if: :cart_recovery?
  # O cupom é criado manualmente na Shopify por fora — aqui só guarda o código
  # já pronto, não gera nada via API.
  validates :coupon_code, presence: true, if: -> { cart_recovery? && include_coupon? }
  validates :start_date, presence: true
  # A recuperação de carrinho pode ficar sem data final (roda até ser desligada).
  validates :end_date, presence: true, unless: :cart_recovery?
  validate :end_date_after_start_date
  validate :whatsapp_template_from_same_client
  validate :meta_template_when_active, if: -> { cart_recovery? && active? }

  # Caixa "Sem data final" do formulário: marcada, apaga a data final.
  attribute :no_end_date, :boolean, default: false
  before_validation { self.end_date = nil if no_end_date && cart_recovery? }

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
  scope :running,  -> {
    active.where('start_date <= ?', Date.current).where('end_date IS NULL OR end_date >= ?', Date.current)
  }

  def running?
    active? && start_date <= Date.current && (end_date.nil? || end_date >= Date.current)
  end

  def status
    return :inactive unless active?
    return :pending  if start_date > Date.current
    return :finished if end_date && end_date < Date.current

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

  def actions_count = automation_actions.count
  def sent_count    = automation_actions.sent.count
  def pending_count = automation_actions.pending.count
  def failed_count  = automation_actions.failed.count

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

  # A recuperação de carrinho só envia modelo cadastrado e aprovado na Meta.
  # Desligada, salva sem modelo (para deixar datas e cupom prontos antes da aprovação).
  def meta_template_when_active
    if whatsapp_template.nil?
      errors.add(:whatsapp_template, 'precisa ser um modelo cadastrado na Meta para ativar a automação')
    elsif !whatsapp_template.approved?
      errors.add(:whatsapp_template, "\"#{whatsapp_template.label}\" ainda não foi aprovado pela Meta")
    end
  end

  def whatsapp_template_from_same_client
    return if whatsapp_template.nil? || whatsapp_template.client_id == client_id

    errors.add(:whatsapp_template, 'não pertence a esta loja')
  end
end
