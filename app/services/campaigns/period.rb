module Campaigns
  class Period
    PRESETS = {
      '7d' => 'Últimos 7 dias', '30d' => 'Últimos 30 dias', 'month' => 'Este mês', '60d' => 'Últimos 60 dias',
      '90d' => 'Últimos 90 dias', '12m' => 'Últimos 12 meses', 'all' => 'Desde o início'
    }.freeze
    DEFAULT = '30d'.freeze

    attr_reader :key, :from, :to

    def self.from_params(params, today: Time.zone.today)
      new(params[:periodo], params[:de], params[:ate], today:)
    end

    def initialize(key, from, to, today: Time.zone.today)
      key = key.presence_in(PRESETS.keys + ['custom']) || DEFAULT
      range = key == 'custom' ? custom_range(from, to) : preset_range(key, today)
      unless range
        key = DEFAULT
        range = preset_range(key, today)
      end
      @key = key
      @from, @to = range
    end

    def time_range
      (from&.in_time_zone&.beginning_of_day)..to.in_time_zone.end_of_day
    end

    def label
      return PRESETS['all'] unless from

      "#{I18n.l(from, format: '%d/%m/%Y')} - #{I18n.l(to, format: '%d/%m/%Y')}"
    end

    private

    def preset_range(key, today)
      case key
      when '7d' then [today - 6, today]
      when '30d' then [today - 29, today]
      when '60d' then [today - 59, today]
      when '90d' then [today - 89, today]
      when 'month' then [today.beginning_of_month, today]
      when '12m' then [today - 1.year + 1.day, today]
      else [nil, today]
      end
    end

    def custom_range(from, to)
      first = parse(from)
      last = parse(to)
      return unless first && last

      [first, last].minmax
    end

    def parse(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
