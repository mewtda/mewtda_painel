module Billing
  # Roda todo dia pelo Heroku Scheduler: para o mês que acabou de fechar, cria
  # no Asaas a cobrança da Fatura de cada cliente ativo que ainda não tem uma.
  # Cliente sem CPF/CNPJ ou com fatura zerada fica de fora.
  class MonthlyChargesJob < ApplicationJob
    queue_as :default

    def perform(month = nil)
      unless AsaasApi.configured?
        Rails.logger.warn('[Billing::MonthlyChargesJob] ASAAS_API_KEY não configurada — nada a fazer.')
        return
      end

      month = month ? Date.parse(month.to_s) : Time.zone.today.prev_month
      api = AsaasApi.new
      Client.where(active: true).where.not(billing_document: [nil, '']).find_each do |client|
        MonthlyCharge.new(client, month, api: api).call
      end
    end
  end
end
