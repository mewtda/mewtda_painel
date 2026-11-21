module Billing
  # Fatura do mês: valor do plano + e-mails enviados + taxa da plataforma por mensagem de WhatsApp de
  # campanha (API Oficial). A tarifa da própria mensagem a Meta cobra direto da loja, no app da Meta.
  class Invoice
    EMAIL_PRICE_PER_THOUSAND = BigDecimal('4')
    WHATSAPP_PRICE_PER_MESSAGE = BigDecimal('0.10')

    attr_reader :client, :month

    def initialize(client, month = Time.zone.today.beginning_of_month)
      @client = client
      @month = month.beginning_of_month
    end

    def plan_name = client.plan_name.presence
    def plan_price = client.plan_price.to_d

    def emails_sent
      @emails_sent ||= Usage.new(client).count('email', month..month.end_of_month)
    end

    def emails_amount
      (emails_sent * EMAIL_PRICE_PER_THOUSAND / 1000).round(2)
    end

    def whatsapp_messages_sent
      @whatsapp_messages_sent ||= Usage.new(client).campaign_whatsapp_count(month.beginning_of_day..month.end_of_month.end_of_day)
    end

    def whatsapp_amount
      (whatsapp_messages_sent * WHATSAPP_PRICE_PER_MESSAGE).round(2)
    end

    def total = plan_price + emails_amount + whatsapp_amount

    def current? = month == Time.zone.today.beginning_of_month
  end
end
