class Client < ApplicationRecord
  # Roda antes dos `dependent:` abaixo: os pedidos apontam para landing pages e os eventos de e-mail para
  # campanhas, então os dados da loja saem primeiro.
  before_destroy :purge_store_data, prepend: true

  has_many :users, dependent: :nullify
  has_many :automations, dependent: :destroy
  has_many :ad_costs, dependent: :destroy
  has_many :refunds, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :abandoned_checkouts, dependent: :destroy
  has_one :popup, dependent: :destroy
  has_one :back_in_stock_setting, dependent: :destroy
  has_many :back_in_stock_alerts, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :whatsapp_templates, dependent: :destroy
  has_many :email_suppressions, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :message_usages, dependent: :delete_all
  has_many :customer_profiles, dependent: :delete_all
  has_many :customers, dependent: :nullify
  has_many :segments, dependent: :destroy
  has_many :landing_pages, dependent: :destroy
  has_many :billing_charges, dependent: :destroy
  has_many :conversion_insights, dependent: :destroy
  has_many :custom_automation_settings, dependent: :delete_all
  has_one_attached :logo

  validates :plan_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :daily_whatsapp_limit, :daily_email_limit,
            numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Contato de cobrança: para onde o Asaas manda a Fatura (às vezes é o financeiro, não o dono da loja).
  # Obrigatório para quem é cobrado (tem CPF/CNPJ); só é checado quando os dados de cobrança mudam, para
  # não travar outras edições de clientes antigos.
  validates :billing_email, :billing_phone, presence: true,
                                            if: -> { billing_document.present? && billing_contact_changing? }
  validates :billing_email, format: { with: URI::MailTo::EMAIL_REGEXP, message: 'não parece um e-mail válido' },
                            allow_blank: true
  validate :billing_phone_must_be_valid, if: -> { billing_phone.present? }

  # Celular de cobrança só com DDD + número (o Asaas não aceita o +55).
  def billing_phone_digits
    digits = billing_phone.to_s.gsub(/\D/, '')
    digits = digits.delete_prefix('55') if digits.length > 11
    digits.presence
  end

  # Aceita preço no formato brasileiro ("1.299,90") vindo do formulário do admin.
  def plan_price=(value)
    value = value.delete('.').tr(',', '.') if value.is_a?(String) && value.include?(',')
    super
  end

  LOGO_CONTENT_TYPES = %w[image/png image/jpeg image/avif].freeze
  LOGO_MAX_SIZE = 2.megabytes

  encrypts :meta_access_token, :google_ads_refresh_token, :shopify_api_secret, :shopify_storefront_token,
           :whatsapp_cloud_access_token

  before_validation :generate_slug, if: -> { slug.blank? && name.present? }

  validates :name, presence: true
  validates :email, presence: true
  validates :site_url, format: { with: %r{\Ahttps?://}, message: 'deve começar com http:// ou https://' },
                       allow_blank: true
  validates :email_sending_domain,
            format: { with: /\A([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}\z/i,
                      message: 'não parece um domínio válido' },
            allow_blank: true
  validate :logo_must_be_png_or_jpeg, if: -> { logo.attached? }
  validate :logo_must_be_small, if: -> { logo.attached? }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: LandingPage::SLUG_FORMAT, message: 'use só letras minúsculas, números e hífens' },
                   exclusion: { in: LandingPage::RESERVED_PREFIXES, message: 'é reservado pelo sistema' }

  def site_url_configured?
    site_url.present?
  end

  # API Oficial do WhatsApp (Cloud API da Meta): o único canal de WhatsApp do painel.
  def whatsapp_cloud_configured?
    whatsapp_cloud_phone_number_id.present? && whatsapp_cloud_access_token.present?
  end

  # Pronto para enviar pela API Oficial: número, conta (WABA) e token preenchidos.
  def whatsapp_ready?
    whatsapp_cloud_configured? && whatsapp_cloud_business_account_id.present?
  end

  def shopify_configured?
    shopify_shop_url.present? && shopify_access_token.present?
  end

  def shopify_admin_handle
    shopify_shop_url.to_s.sub(%r{\Ahttps?://}, '').split('.').first
  end

  def storefront_configured?
    shopify_shop_url.present? && shopify_storefront_token.present?
  end

  def shopify_app_configured?
    shopify_api_key.present? && shopify_api_secret.present?
  end

  def meta_configured?
    meta_access_token.present? && meta_ad_account_id.present?
  end

  def google_ads_configured?
    google_ads_refresh_token.present? && google_ads_customer_id.present?
  end

  def ses_domain_verified?
    ses_verification_status == 'verified'
  end

  def tools_email_domain
    ses_domain_verified? ? email_sending_domain : ENV['SHARED_EMAIL_DOMAIN'].presence
  end

  def storefront_url
    (site_url.presence || shopify_shop_url).to_s.sub(%r{\A(?!https?://)}, 'https://').delete_suffix('/')
  end

  def clear_email_sending!
    update!(email_sending_domain: nil, ses_dkim_tokens: [], ses_verification_status: 'unverified', ses_verified_at: nil)
  end

  # Registros CNAME do Easy DKIM da SES — cada token vira um registro que o
  # cliente precisa cadastrar no DNS do domínio pra provar a propriedade e
  # habilitar o DKIM (formato padrão da AWS quando a identidade é criada sem
  # configuração de assinatura customizada).
  def ses_dns_records
    return [] if email_sending_domain.blank? || ses_dkim_tokens.blank?

    ses_dkim_tokens.map do |token|
      {
        name: "#{token}._domainkey.#{email_sending_domain}",
        type: 'CNAME',
        value: "#{token}.dkim.amazonses.com"
      }
    end
  end

  private

  # Dados da loja sem associação com `dependent:` (volumosos, apagados direto no banco), na ordem das
  # chaves estrangeiras.
  def purge_store_data
    purge_order_references
    [EmailEvent, Order, Product, Location, ShopifyEvent, IntegrationUser, CustomAutomationRun,
     AdCostSnapshot].each { |model| model.where(client_id: id).delete_all }
  end

  def purge_order_references
    orders = Order.where(client_id: id).select(:id)
    AutomationAction.where(order_id: orders).delete_all
    Refund.where(order_id: orders).or(Refund.where(client_id: id)).delete_all
    OrderItem.where(order_id: orders).or(OrderItem.where(product_id: Product.where(client_id: id).select(:id)))
             .delete_all
  end

  def billing_contact_changing?
    will_save_change_to_billing_document? || will_save_change_to_billing_email? || will_save_change_to_billing_phone?
  end

  def billing_phone_must_be_valid
    errors.add(:billing_phone, 'informe com DDD, ex.: (31) 99999-9999') unless billing_phone_digits.to_s.length.between?(10, 11)
  end

  def logo_must_be_png_or_jpeg
    errors.add(:logo, 'deve ser PNG, JPG ou AVIF') unless logo.content_type.in?(LOGO_CONTENT_TYPES)
  end

  def logo_must_be_small
    errors.add(:logo, 'deve ter no máximo 2 MB') if logo.byte_size > LOGO_MAX_SIZE
  end

  def generate_slug
    base = name.parameterize.presence || 'cliente'
    candidate = base
    suffix = 1
    while Client.where.not(id: id).exists?(slug: candidate) || LandingPage::RESERVED_PREFIXES.include?(candidate)
      suffix += 1
      candidate = "#{base}-#{suffix}"
    end
    self.slug = candidate
  end
end
