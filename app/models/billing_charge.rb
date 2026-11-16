# Cobrança da Fatura de um cliente num mês, criada no Asaas pelo
# Billing::MonthlyChargesJob depois que o mês fecha. Uma por cliente e mês.
class BillingCharge < ApplicationRecord
  STATUS_LABELS = {
    'pending' => 'Gerando cobrança',
    'created' => 'Aguardando pagamento',
    'failed' => 'Erro ao gerar cobrança'
  }.freeze

  belongs_to :client

  validates :month, :amount, presence: true
  validates :status, inclusion: { in: STATUS_LABELS.keys }

  def status_label
    STATUS_LABELS[status]
  end

  def external_reference
    "mewtda-client-#{client_id}-#{month.strftime('%Y-%m')}"
  end
end
