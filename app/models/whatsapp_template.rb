# Modelo de mensagem do WhatsApp (API Oficial), criado no painel e aprovado pela Meta.
class WhatsappTemplate < ApplicationRecord
  STATUSES = %w[draft pending approved rejected paused disabled].freeze
  STATUS_LABELS = { 'draft' => 'Rascunho', 'pending' => 'Em análise', 'approved' => 'Aprovado',
                    'rejected' => 'Rejeitado', 'paused' => 'Pausado pela Meta', 'disabled' => 'Desativado' }.freeze
  VARIABLE = '{{1}}'.freeze
  NAME_FORMAT = /\A[a-z0-9_]{1,512}\z/

  belongs_to :client

  scope :approved, -> { where(status: 'approved') }
  scope :ordered, -> { order(updated_at: :desc) }

  before_validation :generate_name, if: -> { name.blank? && label.present? }

  validates :label, presence: true, length: { maximum: 120 }
  validates :body, presence: true, length: { maximum: 1024 }
  validates :footer, length: { maximum: 60 }
  validates :button_text, length: { maximum: 25 }
  validates :button_url, format: { with: %r{\Ahttps?://\S+\z}, message: 'deve começar com http:// ou https://' },
                         allow_blank: true
  validates :name, presence: true, format: { with: NAME_FORMAT }, uniqueness: { scope: :client_id }
  validates :status, inclusion: { in: STATUSES }
  validate :only_first_variable
  validates :body_example, presence: { message: 'é obrigatório quando a mensagem usa o nome do cliente' },
                           if: :uses_variable?
  validate :button_needs_both

  def uses_variable? = body.to_s.include?(VARIABLE)
  def editable? = status.in?(%w[draft rejected])
  def approved? = status == 'approved'
  def status_label = STATUS_LABELS.fetch(status, status)

  def preview_body(first_name = 'Maria')
    body.to_s.gsub(VARIABLE, first_name.to_s)
  end

  def meta_payload
    body_component = { type: 'BODY', text: body }
    body_component[:example] = { body_text: [[body_example]] } if uses_variable?
    components = [body_component]
    components << { type: 'FOOTER', text: footer } if footer.present?
    if button_text.present? && button_url.present?
      components << { type: 'BUTTONS', buttons: [{ type: 'URL', text: button_text, url: button_url }] }
    end
    { name:, category:, language:, components: }
  end

  # Envia para aprovação da Meta. Em erro, deixa a mensagem da Meta em errors[:base] e devolve false.
  def submit!
    api = Whatsapp::Cloud::Api.new(client)
    if meta_id.present?
      api.update_template(meta_id, { components: meta_payload[:components] })
      return update!(status: 'pending', rejection_reason: nil, synced_at: Time.current)
    end

    response = api.create_template(meta_payload)
    update!(meta_id: response['id'], status: response['status'].to_s.downcase.presence_in(STATUSES) || 'pending',
            rejection_reason: nil, synced_at: Time.current)
    true
  rescue Whatsapp::Cloud::Api::Error => e
    errors.add(:base, e.message)
    false
  end

  private

  def generate_name
    base = label.to_s.parameterize(separator: '_').first(500).presence || 'modelo'
    candidate = base
    n = 1
    scope = WhatsappTemplate.where(client_id:)
    while scope.where(name: candidate).where.not(id:).exists?
      n += 1
      candidate = "#{base}_#{n}"
    end
    self.name = candidate
  end

  def only_first_variable
    others = body.to_s.scan(/\{\{\s*(\w+)\s*\}\}/).flatten - ['1']
    errors.add(:body, 'só pode usar a variável {{1}} (primeiro nome do cliente)') if others.any?
  end

  def button_needs_both
    return if button_text.blank? == button_url.blank?

    errors.add(:button_url, 'e o texto do botão precisam ser preenchidos juntos')
  end
end
