module Campaigns
  # Janela de envio por dia da semana e horário (ex.: segunda, quarta e quinta,
  # das 08:00 às 12:00). Fora da janela a campanha espera a próxima abertura.
  class SendWindow
    SHORT_DAYS = %w[Dom Seg Ter Qua Qui Sex Sáb].freeze

    attr_reader :days, :start_minute, :end_minute

    def initialize(days:, from:, to:)
      @days = Array(days).map(&:to_i).select { |day| (0..6).cover?(day) }.uniq.sort
      @start_minute = minutes(from)
      @end_minute = minutes(to)
    end

    def valid? = days.any? && start_minute < end_minute

    def open?(time = Time.current)
      time = time.in_time_zone
      valid? && days.include?(time.wday) && (start_minute...end_minute).cover?((time.hour * 60) + time.min)
    end

    # Primeiro instante em que a janela está aberta, a partir de `time`.
    def next_opening(time = Time.current)
      return unless valid?

      time = time.in_time_zone
      return time if open?(time)

      (0..7).each do |offset|
        day = time.to_date + offset
        opening = Time.zone.local(day.year, day.month, day.day, start_minute / 60, start_minute % 60)
        return opening if days.include?(day.wday) && opening > time
      end
    end

    def hours_per_day = (end_minute - start_minute) / 60.0

    def summary
      return 'Sem janela definida' unless valid?

      names = days.map { |day| SHORT_DAYS[day] }
      list = names.size > 1 ? "#{names[0..-2].join(', ')} e #{names.last}" : names.first
      "#{list}, das #{format_minutes(start_minute)} às #{format_minutes(end_minute)}"
    end

    private

    def minutes(value)
      return value.to_i if value.is_a?(Integer)

      hour, minute = value.to_s.split(':').map(&:to_i)
      (hour.to_i.clamp(0, 23) * 60) + minute.to_i.clamp(0, 59)
    end

    def format_minutes(total) = format('%<h>02d:%<m>02d', h: total / 60, m: total % 60)
  end
end
