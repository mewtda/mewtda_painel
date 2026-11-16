module Billing
  # Cria no Asaas a cobrança da Fatura de um cliente num mês já fechado.
  # Idempotente: a linha em billing_charges é única por cliente/mês e, antes
  # de criar, procura no Asaas uma cobrança com o mesmo externalReference.
  class MonthlyCharge
    DUE_IN_DAYS = 5

    def initialize(client, month, api: AsaasApi.new)
      @client = client
      @month = month.beginning_of_month
      @api = api
    end

    def call
      invoice = Invoice.new(@client, @month)
      return if invoice.total <= 0 || @client.billing_document.blank?

      charge = find_or_create_charge(invoice.total)
      return charge if charge.status == 'created'

      payment = @api.find_payment(charge.external_reference) || create_payment(charge)
      charge.update!(status: 'created', asaas_payment_id: payment['id'], invoice_url: payment['invoiceUrl'],
                     due_date: payment['dueDate'], error_message: nil)
      charge
    rescue AsaasApi::Error => e
      charge&.update!(status: 'failed', error_message: e.message)
      Rails.logger.error("[Billing::MonthlyCharge] client #{@client.id} #{@month}: #{e.message}")
      charge
    end

    private

    def find_or_create_charge(amount)
      BillingCharge.create_with(amount: amount).find_or_create_by!(client: @client, month: @month)
    rescue ActiveRecord::RecordNotUnique
      BillingCharge.find_by!(client: @client, month: @month)
    end

    def create_payment(charge)
      @api.create_payment(customer: asaas_customer_id, value: charge.amount,
                          due_date: Time.zone.today + DUE_IN_DAYS,
                          description: "Mewtda · Fatura de #{I18n.l(@month, format: '%B/%Y')} · #{@client.name}",
                          external_reference: charge.external_reference)
    end

    def asaas_customer_id
      return @client.asaas_customer_id if @client.asaas_customer_id.present?

      document = @client.billing_document.gsub(/\D/, '')
      customer = @api.find_customer(document) ||
                 @api.create_customer(name: @client.name, cpf_cnpj: document, email: @client.email)
      @client.update_columns(asaas_customer_id: customer['id'])
      customer['id']
    end
  end
end
