class LandingPage < ApplicationRecord
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  # Primeiro segmento de rotas/arquivos que já existem no app — uma página não
  # pode usar nenhum deles como prefixo, senão sombreia (ou é sombreada por) eles.
  RESERVED_PREFIXES = %w[
    crm widget integrations assets rails cable sidekiq up api admin
    shopify google_ads widget-assets packs favicon robots carrinho
  ].freeze

  # Atributo de carrinho gravado pela página ao criar o checkout. O "_" na
  # frente esconde o atributo do comprador no checkout; a Shopify devolve ele
  # em note_attributes do pedido (ver Shopify::Orders).
  ATTRIBUTION_KEY = '_landing_page'.freeze

  TEMPLATES_DIR = Rails.root.join('app/views/landing_pages/templates')

  belongs_to :client
  has_many :leads, class_name: 'LandingPageLead', dependent: :destroy
  has_many :orders, dependent: :nullify

  before_validation :default_path_prefix
  before_validation :normalize_product_handles

  validates :name, :template, presence: true
  validates :path_prefix, presence: true, format: { with: SLUG_FORMAT, message: 'use só letras minúsculas, números e hífens' },
                          exclusion: { in: RESERVED_PREFIXES, message: 'é reservado pelo sistema' }
  validates :slug, presence: true, format: { with: SLUG_FORMAT, message: 'use só letras minúsculas, números e hífens' },
                   uniqueness: { scope: :path_prefix, message: 'já está em uso com esse prefixo' }
  validates :template, inclusion: { in: ->(_) { templates } }

  scope :active, -> { where(active: true) }

  def self.templates
    Dir[TEMPLATES_DIR.join('*.html.erb')].map { |path| File.basename(path, '.html.erb') }.sort
  end

  def public_path
    "/#{path_prefix}/#{slug}"
  end

  def sales_open?
    ends_at.blank? || ends_at.future?
  end

  def lead_tag
    "lp-#{path_prefix}-#{slug}"
  end

  # Campo de formulário: handles separados por vírgula/linha.
  def product_handles_text
    product_handles.join("\n")
  end

  def product_handles_text=(value)
    self.product_handles = value.to_s.split(/[\s,]+/)
  end

  def attributed_orders
    orders.where(cancelled_at: nil)
  end

  private

  def default_path_prefix
    self.path_prefix = client&.slug if path_prefix.blank?
  end

  # Aceita handle ("camiseta-ladrao"), ID numérico ("10790042206502"), GID ou
  # o link do produto no admin da Shopify (".../products/10790042206502").
  # IDs viram GID; handles ficam em minúsculas.
  def normalize_product_handles
    self.product_handles = Array(product_handles).filter_map { |ref| self.class.normalize_product_ref(ref) }.uniq
  end

  def self.normalize_product_ref(ref)
    ref = ref.to_s.strip
    return nil if ref.blank?

    id = ref[%r{/products/(\d+)}, 1] || ref[%r{\Agid://shopify/Product/(\d+)\z}i, 1] || ref[/\A(\d+)\z/, 1]
    id ? "gid://shopify/Product/#{id}" : ref.downcase
  end
end
