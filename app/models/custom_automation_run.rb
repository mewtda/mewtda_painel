# Uma execução de "Automação personalizada" — rotinas feitas sob medida pra um
# cliente específico (ver CustomAutomations::Registry). Hoje a única é a nota de
# transferência mensal da Fernanda Farah: lê os pedidos do período na Shopify,
# monta uma NF de transferência da matriz pro e-commerce no Tiny (sem emitir),
# guarda os itens pra conferência e só emite quando alguém aprova.
class CustomAutomationRun < ApplicationRecord
  STATUSES = %w[pending processing awaiting_review emitting emitted failed discarded].freeze

  STATUS_LABELS = {
    'pending' => 'Na fila',
    'processing' => 'Gerando nota',
    'awaiting_review' => 'Aguardando conferência',
    'emitting' => 'Emitindo',
    'emitted' => 'Emitida',
    'failed' => 'Erro',
    'discarded' => 'Descartada'
  }.freeze

  ORDER_FILTERS = {
    'paid' => 'Somente pagos (sem cancelados, descontando reembolsos)',
    'not_cancelled' => 'Todos exceto cancelados (descontando reembolsos)',
    'all' => 'Todos os pedidos do período'
  }.freeze

  belongs_to :client
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: ->(_) { CustomAutomations::Registry.kinds } }
  validates :status, inclusion: { in: STATUSES }
  validates :order_filter, inclusion: { in: ORDER_FILTERS.keys }
  validates :period_start, :period_end, presence: true
  validates :price_percentage, numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validate :period_order

  scope :recent, -> { order(created_at: :desc) }

  def status_label
    STATUS_LABELS[status]
  end

  def order_filter_label
    ORDER_FILTERS[order_filter]
  end

  def automation
    CustomAutomations::Registry.find(kind)
  end

  def in_progress?
    status.in?(%w[pending processing emitting])
  end

  def emittable?
    status == 'awaiting_review' && tiny_note_id.present?
  end

  def discardable?
    status.in?(%w[awaiting_review failed])
  end

  # A nota fica na conta Tiny da matriz — o link só abre logado nela.
  def tiny_note_url
    "https://erp.tiny.com.br/notas_fiscais#edit/#{tiny_note_id}" if tiny_note_id.present?
  end

  def total_quantity
    items.sum { |i| i['quantity'].to_i }
  end

  private

  def period_order
    return if period_start.blank? || period_end.blank?

    errors.add(:period_end, 'deve ser igual ou posterior ao início') if period_end < period_start
  end
end
