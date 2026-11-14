module BackInStock
  class AlertFilter
    NOTICE_STATUSES = { 'clique' => 'Clicado', 'abriu' => 'Aberto', 'entregue' => 'Entregue', 'devolvido' => 'Não entregue',
                        'denuncia' => 'Denúncia', 'sem_rastreio' => 'Enviado' }.freeze
    BOUGHT = { 'sim' => 'Comprou', 'nao' => 'Não comprou' }.freeze
    MAX_LIST = 12
    SIZE_MATCH = 'EXISTS (SELECT 1 FROM unnest(string_to_array(back_in_stock_alerts.variant_title, \' / \')) AS part ' \
                       "WHERE UPPER(SPLIT_PART(part, '/', 1)) IN (:sizes))".freeze
    CATEGORY_MATCH = 'EXISTS (SELECT 1 FROM products p, unnest(string_to_array(p.tags, \',\')) AS item_tag ' \
                     'WHERE p.client_id = back_in_stock_alerts.client_id ' \
                     'AND p.shopify_product_id = back_in_stock_alerts.shopify_product_id::text ' \
                     'AND LOWER(BTRIM(item_tag)) IN (:categories))'.freeze

    def initialize(client, params, status:)
      @client = client
      @status = status
      @from = date(params[:de])
      @to = date(params[:ate])
      @sizes = list(params[:tamanho]).map(&:upcase)
      @categories = list(params[:categoria])
      @age = params[:espera].presence_in(BackInStockAlert::AGE_BUCKETS.map(&:first))
      @min_demand = params[:demanda].to_i.clamp(0, 9_999).then { |value| value if value.positive? }
      @notice = (params[:aviso].presence_in(NOTICE_STATUSES.keys) if notified?)
      @bought = (params[:comprou].presence_in(BOUGHT.keys) if notified?)
    end

    attr_reader :min_demand

    def apply(scope)
      scope = scope.where(created_at: time_range) if @from || @to
      scope = scope.where(sanitize(SIZE_MATCH, sizes: @sizes)) if @sizes.any?
      scope = scope.where(sanitize(CATEGORY_MATCH, categories: @categories.map(&:downcase))) if @categories.any?
      scope = scope.where(created_at: age_range) if @age
      scope = notice(scope) if @notice
      @bought ? bought(scope) : scope
    end

    def to_params
      { de: @from&.iso8601, ate: @to&.iso8601, tamanho: presence(@sizes), categoria: presence(@categories), espera: @age,
        demanda: @min_demand, aviso: @notice, comprou: @bought }.compact
    end

    def chips
      params = to_params
      params.keys.map { |key| key.in?(%i[de ate]) ? :periodo : key }.uniq.map do |key|
        { label: label(key), params: params.except(*(key == :periodo ? %i[de ate] : [key])) }
      end
    end

    def active_count = chips.size

    private

    attr_reader :client

    def notified? = @status == 'notified'

    def label(key)
      case key
      when :periodo then period_label
      when :tamanho then "Tamanho: #{@sizes.join(', ')}"
      when :categoria then "Categoria: #{@categories.join(', ')}"
      when :espera then "Solicitado há: #{BackInStockAlert::AGE_BUCKETS.find { |item| item.first == @age }[1].downcase}"
      when :demanda then "Pelo menos #{@min_demand} #{'pessoa'.pluralize(@min_demand)}"
      when :aviso then "Aviso: #{NOTICE_STATUSES.fetch(@notice)}"
      when :comprou then BOUGHT.fetch(@bought)
      end
    end

    def period_label
      first = ("de #{I18n.l(@from, format: '%d/%m/%Y')}" if @from)
      last = ("até #{I18n.l(@to, format: '%d/%m/%Y')}" if @to)
      "Período: #{[first, last].compact.join(' ')}"
    end

    def time_range
      (@from&.in_time_zone&.beginning_of_day)..(@to&.in_time_zone&.end_of_day)
    end

    def age_range
      _, _, days = BackInStockAlert::AGE_BUCKETS.find { |key, *| key == @age }
      days.end&.days&.ago..days.begin.days.ago
    end

    def bought(scope)
      ids = Attribution.new(client).ordered_alert_ids
      @bought == 'sim' ? scope.where(id: ids) : scope.where.not(id: ids)
    end

    def notice(scope) = scope.where(notice_clause)

    def notice_clause
      has = lambda do |type|
        "EXISTS (SELECT 1 FROM email_events e WHERE e.back_in_stock_alert_id = back_in_stock_alerts.id AND e.event_type = '#{type}')"
      end
      none = ->(*types) { types.map { |type| "NOT #{has.call(type)}" }.join(' AND ') }
      {
        'clique' => has.call('click'),
        'abriu' => "#{has.call('open')} AND #{none.call('click')}",
        'entregue' => "#{has.call('delivery')} AND #{none.call('click', 'open', 'bounce', 'complaint')}",
        'devolvido' => "#{has.call('bounce')} AND #{none.call('complaint')}",
        'denuncia' => has.call('complaint'),
        'sem_rastreio' => none.call('delivery', 'open', 'click', 'bounce', 'complaint')
      }.fetch(@notice)
    end

    def sanitize(sql, binds = {}) = ActiveRecord::Base.sanitize_sql_array([sql, binds])

    def list(value) = Array(value).map { |item| item.to_s.strip.first(80) }.compact_blank.first(MAX_LIST)

    def presence(list) = (list if list.any?)

    def date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end
  end
end
