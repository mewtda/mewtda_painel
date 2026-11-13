module Billing
  # Fatura do mês: valor do plano + e-mails enviados no mês.
  class Invoice
    EMAIL_PRICE_PER_THOUSAND = BigDecimal('4')

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

    def total = plan_price + emails_amount

    def current? = month == Time.zone.today.beginning_of_month
  end
end
