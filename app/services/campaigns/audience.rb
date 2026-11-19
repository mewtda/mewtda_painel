module Campaigns
  # Quem recebe uma mensagem da campanha, a partir da união dos segmentos escolhidos.
  # E-mail: perfis com e-mail fora da lista de recusa (quem é inscrito em marketing é só informado;
  # a loja decide se envia para quem não consentiu).
  # WhatsApp: perfis com telefone válido, sem repetir o mesmo número.
  class Audience
    Result = Struct.new(:total, :without_email, :suppressed, :recipients, :subscribed, :not_subscribed,
                        :without_phone, :cost, :daily_limit, :used_today, keyword_init: true)

    def initialize(client, segments, channel: 'email')
      @client = client
      @segments = Array(segments).compact
      @channel = channel.to_s
    end

    def call
      base = { daily_limit: usage.daily_limit(@channel), used_today: usage.today(@channel) }
      return Result.new(**whatsapp_counts, cost: 0, **base) if whatsapp?

      Result.new(**email_counts, cost:, **base)
    end

    # Perfis que de fato recebem (base do envio em lote), sem repetir perfil.
    def recipients_scope
      whatsapp? ? profiles.where.not(phone: [nil, '']) : with_email.where.not(suppressed_sql)
    end

    # Cada destinatário uma vez: |perfil, endereço| — e-mail em minúsculas ou telefone normalizado (+55...).
    def each_recipient
      seen = Set.new
      recipients_scope.order(:id).find_each do |profile|
        address = address_for(profile)
        next if address.nil? || !seen.add?(address)

        yield profile, address
      end
    end

    private

    attr_reader :client, :segments

    def whatsapp? = @channel == 'whatsapp'

    def usage = @usage ||= Billing::Usage.new(client)

    def profiles
      return CustomerProfile.none if segments.empty?

      ids = segments.map { |segment| "customer_profiles.id IN (#{segment.profiles.reselect('customer_profiles.id').to_sql})" }
      CustomerProfile.where(client_id: client.id).where(ids.join(' OR '))
    end

    def address_for(profile)
      whatsapp? ? Whatsapp::Phone.normalize(profile.phone) : profile.email.to_s.strip.downcase.presence
    end

    def with_email = profiles.where.not(email: [nil, ''])

    def suppressed_sql
      Arel.sql('EXISTS (SELECT 1 FROM email_suppressions es WHERE es.client_id = customer_profiles.client_id ' \
               'AND es.email = customer_profiles.email)')
    end

    def email_counts
      total = profiles.count
      with_mail = with_email.count
      recipients = recipients_scope
      count = recipients.count
      subscribed = recipients.where(email_marketing_state: 'subscribed').count
      { total:, without_email: total - with_mail, suppressed: with_mail - count, recipients: count,
        subscribed:, not_subscribed: count - subscribed }
    end

    def whatsapp_counts
      total = profiles.count
      numbers = recipients_scope.pluck(:phone).filter_map { |phone| Whatsapp::Phone.normalize(phone) }
      unique = numbers.uniq.size
      { total:, without_phone: total - numbers.size, recipients: unique }
    end

    def cost
      recipients_scope.count * Billing::Invoice::EMAIL_PRICE_PER_THOUSAND / 1000
    end
  end
end
