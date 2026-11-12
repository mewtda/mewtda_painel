class EmailTemplate < ApplicationRecord
  belongs_to :client
  has_one_attached :image
  has_one_attached :image_bottom

  LAYOUTS = %w[image_top image_left image_right image_top_bottom banner].freeze

  enum trigger_kind: {
    manual: 0,
    welcome: 1,
    cart_recovery: 2,
    inactive_customer: 3,
    post_purchase: 4,
    cashback: 5,
    back_in_stock: 6
  }

  TRIGGER_LABELS = {
    'manual' => 'Envio manual',
    'welcome' => 'Boas-vindas (novo cadastro)',
    'cart_recovery' => 'Carrinho abandonado',
    'inactive_customer' => 'Cliente inativo',
    'post_purchase' => 'Pós-compra',
    'cashback' => 'Cashback disponível',
    'back_in_stock' => 'Produto de volta ao estoque'
  }.freeze

  PRESETS = {
    welcome: {
      name: 'Boas-vindas',
      subject: 'Seja bem-vindo(a)!',
      heading: 'Bem-vindo(a)!',
      body: 'Que bom ter você com a gente. Aproveite pra conhecer nossos produtos.',
      button_text: 'Ver produtos',
      layout: 'image_top',
      trigger_kind: 'welcome',
      trigger_config: {}
    },
    promo: {
      name: 'Promoção',
      subject: 'Oferta imperdível por tempo limitado',
      heading: 'Oferta imperdível!',
      body: 'Aproveite as condições especiais que preparamos pra você.',
      button_text: 'Aproveitar agora',
      layout: 'banner',
      trigger_kind: 'manual',
      trigger_config: {}
    },
    cart_recovery: {
      name: 'Carrinho abandonado',
      subject: 'Você esqueceu algo no carrinho',
      heading: 'Ainda dá tempo!',
      body: 'Notamos que você deixou alguns itens no carrinho. Finalize sua compra antes que acabem.',
      button_text: 'Finalizar compra',
      layout: 'image_left',
      trigger_kind: 'cart_recovery',
      trigger_config: { 'delay_hours' => 2 }
    },
    inactive_customer: {
      name: 'Cliente inativo',
      subject: 'Sentimos sua falta!',
      heading: 'Sentimos sua falta!',
      body: 'Faz um tempo que você não aparece por aqui. Que tal dar uma olhada nas novidades?',
      button_text: 'Ver novidades',
      layout: 'image_right',
      trigger_kind: 'inactive_customer',
      trigger_config: { 'inactive_days' => 30 }
    },
    post_purchase: {
      name: 'Pós-compra',
      subject: 'Obrigado pela sua compra!',
      heading: 'Obrigado pela sua compra!',
      body: 'Esperamos que você aproveite. Conta pra gente o que achou!',
      button_text: 'Avaliar compra',
      layout: 'image_top',
      trigger_kind: 'post_purchase',
      trigger_config: { 'days_after_purchase' => 3 }
    },
    cashback: {
      name: 'Cashback disponível',
      subject: 'Você tem cashback disponível!',
      heading: 'Você tem cashback disponível!',
      body: 'Use seu saldo de cashback na próxima compra antes que expire.',
      button_text: 'Usar cashback',
      layout: 'banner',
      trigger_kind: 'cashback',
      trigger_config: {}
    },
    back_in_stock: {
      name: 'De volta ao estoque',
      subject: '{produto} voltou ao estoque!',
      heading: 'Voltou pra você!',
      body: 'O produto que você pediu para ser avisado já está disponível na {loja}. Garanta o seu antes que acabe de novo.',
      button_text: 'Comprar agora',
      layout: 'image_left',
      trigger_kind: 'back_in_stock',
      trigger_config: {}
    }
  }.freeze

  validates :name, :subject, :heading, :body, :button_text, presence: true
  validates :layout, inclusion: { in: LAYOUTS }
  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validates :trigger_delay_hours, presence: true, numericality: { greater_than: 0 }, if: :cart_recovery?
  validates :trigger_inactive_days, presence: true, numericality: { greater_than: 0 }, if: :inactive_customer?
  validates :trigger_days_after_purchase, presence: true, numericality: { greater_than: 0 }, if: :post_purchase?

  # Accessors para os parâmetros armazenados no jsonb :trigger_config — cada
  # trigger_kind usa a sua própria chave, as demais ficam vazias.
  {
    trigger_delay_hours: 'delay_hours',
    trigger_inactive_days: 'inactive_days',
    trigger_days_after_purchase: 'days_after_purchase'
  }.each do |method_name, key|
    define_method(method_name) { trigger_config[key] }
    define_method(:"#{method_name}=") { |v| self.trigger_config = trigger_config.merge(key => v.presence) }
  end

  def trigger_label
    TRIGGER_LABELS.fetch(trigger_kind)
  end

  def self.preset(key)
    return nil if key.blank?

    PRESETS[key.to_sym]
  end
end
