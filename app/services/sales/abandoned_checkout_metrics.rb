module Sales
  # Resumo dos checkouts abandonados do cliente criados no intervalo.
  # Recuperado = checkout com completed_at.
  class AbandonedCheckoutMetrics
    def initialize(client, from:, to:)
      @client = client
      @from = from
      @to = to
    end

    def call
      scope = @client.abandoned_checkouts.where(checkout_created_at: @from..@to)
      count = scope.count
      total = scope.sum(:total_price).to_d
      recovered = scope.where.not(completed_at: nil)

      {
        count: count,
        average_ticket: count.zero? ? 0.to_d : (total / count).round(2),
        total: total,
        recovered_count: recovered.count,
        recovered_total: recovered.sum(:total_price).to_d
      }
    end
  end
end
