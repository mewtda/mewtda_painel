module Campaigns
  # Quem vai receber uma campanha de e-mail: perfis do segmento que têm e-mail e
  # não estão na lista de recusa. Quem é inscrito em marketing é só informado
  # (a loja decide se envia para quem não consentiu).
  class Audience
    Result = Struct.new(:total, :without_email, :suppressed, :recipients, :subscribed, :not_subscribed,
                        :cost, :daily_limit, :used_today, keyword_init: true)

    def initialize(client, segment)
      @client = client
      @segment = segment
    end

    def call
      Result.new(**counts, cost:, daily_limit: usage.daily_limit('email'), used_today: usage.today('email'))
    end

    # Perfis que de fato recebem (base do envio em lote).
    def recipients_scope
      with_email.where.not(suppressed_sql)
    end

    private

    attr_reader :client, :segment

    def usage = @usage ||= Billing::Usage.new(client)

    def profiles = segment ? segment.profiles : CustomerProfile.none

    def with_email = profiles.where.not(email: [nil, ''])

    def suppressed_sql
      Arel.sql('EXISTS (SELECT 1 FROM email_suppressions es WHERE es.client_id = customer_profiles.client_id ' \
               'AND es.email = customer_profiles.email)')
    end

    def counts
      total = profiles.count
      with_mail = with_email.count
      recipients = recipients_scope
      count = recipients.count
      subscribed = recipients.where(email_marketing_state: 'subscribed').count
      { total:, without_email: total - with_mail, suppressed: with_mail - count, recipients: count,
        subscribed:, not_subscribed: count - subscribed }
    end

    def cost
      counts_recipients * Billing::Invoice::EMAIL_PRICE_PER_THOUSAND / 1000
    end

    def counts_recipients = @counts_recipients ||= recipients_scope.count
  end
end
