module Billing
  # Envios de WhatsApp e e-mail de um cliente, e se o limite diário já foi atingido.
  class Usage
    CHANNELS = %w[whatsapp email].freeze

    def initialize(client)
      @client = client
    end

    def count(channel, range)
      channel == 'whatsapp' ? whatsapp_scope(range).count : email_scope(range).sum(:count)
    end

    def today(channel)
      count(channel, today_range(channel))
    end

    def daily_limit(channel)
      limit = channel == 'whatsapp' ? client.daily_whatsapp_limit : client.daily_email_limit
      limit if limit.to_i.positive?
    end

    def limit_reached?(channel)
      limit = daily_limit(channel)
      limit.present? && today(channel) >= limit
    end

    # { Date => quantidade } dos últimos `days` dias, incluindo hoje e dias zerados.
    def daily_series(channel, days: 14)
      first = Time.zone.today - (days - 1)
      counts =
        if channel == 'whatsapp'
          whatsapp_scope(first.beginning_of_day..).group(day_sql('whatsapp_messages.sent_at')).count
                                                   .transform_keys(&:to_date)
        else
          email_scope(first..).group(:day).sum(:count)
        end
      (first..Time.zone.today).index_with { |day| counts.fetch(day, 0) }
    end

    private

    attr_reader :client

    def today_range(channel)
      today = Time.zone.today
      channel == 'whatsapp' ? today.all_day : today..today
    end

    # Só mensagens que saíram pela plataforma (equipe, automações e IA) e que
    # o WhatsApp aceitou (têm provider_id). Mensagens do celular não contam.
    def whatsapp_scope(range)
      Whatsapp::Message.joins(:connection)
                       .where(whatsapp_connections: { client_id: client.id })
                       .where(direction: 'outgoing', historical: false, origin: %w[team automation ai])
                       .where.not(provider_id: nil)
                       .where(sent_at: range)
    end

    def email_scope(range)
      MessageUsage.where(client:, channel: 'email', day: range)
    end

    def day_sql(column)
      Arel.sql(ActiveRecord::Base.sanitize_sql_array(["DATE(#{column} AT TIME ZONE 'UTC' AT TIME ZONE ?)", Time.zone.tzinfo.name]))
    end
  end
end
