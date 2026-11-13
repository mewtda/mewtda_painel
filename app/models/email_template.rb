class EmailTemplate < ApplicationRecord
  belongs_to :client
  has_one_attached :image
  has_one_attached :image_bottom
  # Imagens enviadas pelo editor de blocos (referenciadas por signed_id nos
  # blocos) — anexadas aqui pra serem apagadas junto com o template.
  has_many_attached :block_images

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
    'manual' => 'Campanhas',
    'welcome' => 'Boas-vindas (novo cadastro)',
    'cart_recovery' => 'Carrinho abandonado',
    'inactive_customer' => 'Cliente inativo',
    'post_purchase' => 'Pós-compra',
    'cashback' => 'Cashback disponível',
    'back_in_stock' => 'Produto de volta ao estoque'
  }.freeze

  # Ponto de partida do "Em branco": uma estrutura mínima pra já ver algo no preview.
  BLANK = {
    blocks: [
      { 'type' => 'logo' },
      { 'type' => 'heading', 'text' => 'Seu título aqui' },
      { 'type' => 'text', 'text' => 'Escreva sua mensagem. Use **negrito**, *itálico* e variáveis como {nome}.' },
      { 'type' => 'button', 'text' => 'Ver produtos' }
    ]
  }.freeze

  # Templates prontos da galeria em /email_templates/new — tudo editável depois.
  PRESETS = {
    welcome: {
      name: 'Boas-vindas',
      subject: 'Seja bem-vindo(a) à {loja}!',
      trigger_kind: 'welcome',
      trigger_config: {},
      design: { 'preheader' => 'Que bom ter você com a gente 💜' },
      blocks: [
        { 'type' => 'logo' },
        { 'type' => 'image', 'pad' => 'none' },
        { 'type' => 'heading', 'text' => 'Bem-vindo(a), {nome}!', 'size' => 'xl' },
        { 'type' => 'text', 'text' => 'Que bom ter você com a gente. Separamos o melhor da loja pra você começar com o pé direito.' },
        { 'type' => 'coupon', 'label' => 'Seu presente de boas-vindas', 'code' => 'BEMVINDO10' },
        { 'type' => 'button', 'text' => 'Ver produtos' },
        { 'type' => 'divider' },
        { 'type' => 'social' }
      ]
    },
    promo: {
      name: 'Promoção',
      subject: 'Oferta imperdível por tempo limitado ⏰',
      trigger_kind: 'manual',
      trigger_config: {},
      design: { 'preheader' => 'Só até domingo — corre!' },
      blocks: [
        { 'type' => 'logo' },
        { 'type' => 'heading', 'text' => 'ATÉ 50% OFF', 'size' => 'xl', 'bg' => '#111111', 'color' => '#ffffff', 'pad' => 'lg' },
        { 'type' => 'image', 'pad' => 'none' },
        { 'type' => 'text', 'text' => 'Aproveite as **condições especiais** que preparamos pra você. Estoque limitado!' },
        { 'type' => 'button', 'text' => 'Aproveitar agora', 'full' => true },
        { 'type' => 'gallery', 'items' => [{ 'caption' => 'Novidades' }, { 'caption' => 'Mais vendidos' }, { 'caption' => 'Outlet' }] },
        { 'type' => 'spacer' }
      ]
    },
    cart_recovery: {
      name: 'Carrinho abandonado',
      subject: '{nome}, você esqueceu algo no carrinho',
      trigger_kind: 'cart_recovery',
      trigger_config: { 'delay_hours' => 2 },
      design: { 'preheader' => 'Seus itens ainda estão te esperando' },
      blocks: [
        { 'type' => 'logo' },
        { 'type' => 'image_text', 'heading' => 'Ainda dá tempo!',
          'text' => 'Notamos que você deixou alguns itens no carrinho. Finalize sua compra antes que acabem.',
          'button_text' => 'Finalizar compra' },
        { 'type' => 'coupon', 'label' => 'Um empurrãozinho pra você', 'code' => 'VOLTA10' }
      ]
    },
    inactive_customer: {
      name: 'Cliente inativo',
      subject: 'Sentimos sua falta, {nome}!',
      trigger_kind: 'inactive_customer',
      trigger_config: { 'inactive_days' => 30 },
      design: { 'preheader' => 'Tem muita novidade te esperando' },
      blocks: [
        { 'type' => 'logo' },
        { 'type' => 'heading', 'text' => 'Sentimos sua falta!' },
        { 'type' => 'image_text', 'side' => 'right', 'heading' => 'Chegou coisa nova',
          'text' => 'Faz um tempo que você não aparece por aqui. Que tal dar uma olhada nas novidades?',
          'button_text' => 'Ver novidades' },
        { 'type' => 'social' }
      ]
    },
    post_purchase: {
      name: 'Pós-compra',
      subject: 'Obrigado pela sua compra!',
      trigger_kind: 'post_purchase',
      trigger_config: { 'days_after_purchase' => 3 },
      design: { 'preheader' => 'Conta pra gente o que achou' },
      blocks: [
        { 'type' => 'logo' },
        { 'type' => 'image', 'pad' => 'none' },
        { 'type' => 'heading', 'text' => 'Obrigado pela sua compra, {nome}!' },
        { 'type' => 'text', 'text' => 'Esperamos que você aproveite. Conta pra gente o que achou!' },
        { 'type' => 'button', 'text' => 'Avaliar compra' }
      ]
    },
    cashback: {
      name: 'Cashback disponível',
      subject: 'Você tem cashback disponível!',
      trigger_kind: 'cashback',
      trigger_config: {},
      design: { 'preheader' => 'Use antes que expire' },
      blocks: [
        { 'type' => 'logo' },
        { 'type' => 'heading', 'text' => 'Você tem cashback disponível!', 'size' => 'xl' },
        { 'type' => 'text', 'text' => 'Use seu saldo de cashback na próxima compra **antes que expire**.' },
        { 'type' => 'button', 'text' => 'Usar cashback' }
      ]
    },
    back_in_stock: {
      name: 'De volta ao estoque',
      subject: '{produto} voltou ao estoque!',
      trigger_kind: 'back_in_stock',
      trigger_config: {},
      design: { 'preheader' => 'Garanta o seu antes que acabe de novo' },
      blocks: [
        { 'type' => 'logo' },
        { 'type' => 'heading', 'text' => 'Voltou pra você!' },
        { 'type' => 'text', 'text' => 'O produto que você pediu para ser avisado já está disponível na {loja}. Garanta o seu antes que acabe de novo.' },
        { 'type' => 'product', 'button_text' => 'Comprar agora' }
      ]
    }
  }.freeze

  validates :name, :subject, presence: true
  validates :layout, inclusion: { in: LAYOUTS }
  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }, allow_blank: true
  validate :must_have_blocks
  validates :trigger_delay_hours, presence: true, numericality: { greater_than: 0 }, if: :cart_recovery?
  validates :trigger_inactive_days, presence: true, numericality: { greater_than: 0 }, if: :inactive_customer?
  validates :trigger_days_after_purchase, presence: true, numericality: { greater_than: 0 }, if: :post_purchase?

  after_save :attach_block_images

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

  def blocks=(value)
    super(EmailTemplates::Blocks.sanitize(value))
  end

  def design=(value)
    super(EmailTemplates::Blocks.sanitize_design(value))
  end

  # Campos ocultos do editor, que mandam os blocos/estilo como JSON.
  def blocks_json=(value)
    self.blocks = value
  end

  def design_json=(value)
    self.design = value
  end

  def design
    EmailTemplates::Blocks.sanitize_design(super)
  end

  # Blocos usados pra montar o e-mail. Templates criados antes do editor por
  # blocos (só com heading/body/layout) são convertidos na hora.
  def content_blocks
    stored = self[:blocks]
    stored.present? ? stored : EmailTemplates::LegacyBlocks.new(self).call
  end

  private

  def must_have_blocks
    errors.add(:base, 'Adicione pelo menos um bloco ao e-mail.') if content_blocks.blank?
  end

  def attach_block_images
    attached = block_images.blobs.pluck(:id)
    blobs = EmailTemplates::Blocks.image_ids(self[:blocks]).filter_map { |id| ActiveStorage::Blob.find_signed(id) }
    # Só uploads novos (sem anexo); imagens de templates antigos já pertencem a :image/:image_bottom.
    new_blobs = blobs.uniq(&:id).reject { |blob| attached.include?(blob.id) || blob.attachments.exists? }
    block_images.attach(new_blobs) if new_blobs.any?
  end
end
