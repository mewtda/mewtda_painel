# Modelo de mensagem do WhatsApp (API Oficial). Os modelos são criados e aprovados no Gerenciador do
# WhatsApp da Meta e importados para o painel pela Whatsapp::Cloud::TemplateSync — o painel não cria nem
# edita modelos. Guarda o texto (para prévia), o status na Meta e os números da Meta por modelo.
class WhatsappTemplate < ApplicationRecord
  STATUSES = %w[draft pending approved rejected paused disabled].freeze
  STATUS_LABELS = { 'draft' => 'Rascunho', 'pending' => 'Em análise', 'approved' => 'Aprovado',
                    'rejected' => 'Rejeitado', 'paused' => 'Pausado pela Meta', 'disabled' => 'Desativado' }.freeze
  VARIABLE = '{{1}}'.freeze
  NAME_FORMAT = /\A[a-z0-9_]{1,512}\z/

  belongs_to :client

  scope :approved, -> { where(status: 'approved') }
  # Aprovados que o painel consegue enviar (a Meta permite recursos que o envio ainda não cobre).
  scope :sendable, -> { approved.where(unsupported_reason: nil) }
  scope :ordered, -> { order(updated_at: :desc) }

  before_validation :generate_name, if: -> { name.blank? && label.present? }

  validates :label, presence: true, length: { maximum: 120 }
  validates :name, presence: true, format: { with: NAME_FORMAT }, uniqueness: { scope: :client_id }
  validates :status, inclusion: { in: STATUSES }

  def uses_variable? = body.to_s.include?(VARIABLE)
  def supported? = unsupported_reason.blank?
  def approved? = status == 'approved'
  def status_label = STATUS_LABELS.fetch(status, status)

  def preview_body(first_name = 'Maria')
    body.to_s.gsub(VARIABLE, first_name.to_s)
  end

  def read_rate
    return if stats_delivered.to_i.zero?

    (stats_read.to_f / stats_delivered * 100).round
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
end
