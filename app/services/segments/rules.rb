module Segments
  # Regras de segmento: grupos de condições. Dentro de um grupo todas as
  # condições valem (E); entre grupos basta um (OU).
  #
  #   { "groups" => [ { "conditions" => [ { "field" => "orders_count", "op" => "gte", "value" => "3" } ] } ] }
  #
  # Campos e operadores vêm de listas fechadas; valores sempre entram como
  # parâmetros do SQL.
  class Rules
    NUMBER_OPS = { 'eq' => 'Igual a', 'gt' => 'Maior que', 'gte' => 'Maior ou igual a', 'lt' => 'Menor que',
                   'lte' => 'Menor ou igual a', 'between' => 'Entre' }.freeze
    DATE_OPS = { 'last_days' => 'Nos últimos (dias)', 'more_than_days' => 'Há mais de (dias)', 'after' => 'Depois de',
                 'before' => 'Antes de', 'between' => 'Entre' }.freeze
    TEXT_OPS = { 'contains' => 'Contém', 'equals' => 'É igual a' }.freeze
    LIST_OPS = { 'in' => 'É um de', 'not_in' => 'Não é nenhum de' }.freeze
    BOOL_OPS = { 'yes' => 'Sim', 'no' => 'Não' }.freeze
    SEGMENT_OPS = { 'in' => 'Faz parte', 'not_in' => 'Não faz parte' }.freeze
    ITEM_OPS = { 'in' => 'Comprou' }.freeze

    MARKETING_STATES = { 'subscribed' => 'Inscrito', 'not_subscribed' => 'Não inscrito', 'pending' => 'Pendente',
                         'unsubscribed' => 'Cancelou a inscrição', 'unknown' => 'Sem informação' }.freeze

    OPS = { number: NUMBER_OPS, money: NUMBER_OPS, date: DATE_OPS, text: TEXT_OPS, rfm: LIST_OPS, bool: BOOL_OPS,
            segment: SEGMENT_OPS, marketing: LIST_OPS, categories: ITEM_OPS, sizes: ITEM_OPS }.freeze
    LIST_TYPES = %i[rfm marketing categories sizes].freeze

    P = 'customer_profiles'.freeze

    FIELDS = {
      # Compras
      'orders_count' => { group: 'Compras', label: 'Número de compras', type: :number, column: "#{P}.orders_count" },
      'total_spent' => { group: 'Compras', label: 'Valor total gasto', type: :money, column: "#{P}.total_spent" },
      'avg_ticket' => { group: 'Compras', label: 'Ticket médio', type: :money, column: "#{P}.avg_ticket" },
      'last_order_total' => { group: 'Compras', label: 'Valor da última compra', type: :money, column: "#{P}.last_order_total" },
      'first_order_at' => { group: 'Compras', label: 'Data da primeira compra', type: :date, column: "#{P}.first_order_at" },
      'last_order_at' => { group: 'Compras', label: 'Data da última compra', type: :date, column: "#{P}.last_order_at" },
      'purchase_date' => { group: 'Compras', label: 'Comprou no período', type: :date, exists: :order_date },
      'coupons_used' => { group: 'Cupom', label: 'Compras com cupom', type: :number, column: "#{P}.coupons_used" },
      'coupon_code' => { group: 'Cupom', label: 'Usou o cupom', type: :text, exists: :coupon },
      'staff' => { group: 'Compras', label: 'Comprou com o vendedor', type: :text, exists: :staff },
      # Produto
      'product' => { group: 'Produto', label: 'Produto em qualquer compra', type: :text, exists: :product },
      'not_product' => { group: 'Produto', label: 'Nunca comprou o produto', type: :text, exists: :product, negate: true },
      'product_tag' => { group: 'Produto', label: 'Comprou produto com a tag', type: :text, exists: :product_tag },
      'product_category' => { group: 'Produto', label: 'Comprou produto da categoria', type: :categories, item: :category },
      'product_size' => { group: 'Produto', label: 'Comprou produto no tamanho', type: :sizes, item: :size },
      # Dados do cliente
      'rfm_segment' => { group: 'Dados do cliente', label: 'Perfil RFM', type: :rfm, column: "#{P}.rfm_segment" },
      'name' => { group: 'Dados do cliente', label: 'Nome', type: :text, column: "#{P}.name" },
      'email' => { group: 'Dados do cliente', label: 'E-mail', type: :text, column: "#{P}.email" },
      'city' => { group: 'Dados do cliente', label: 'Cidade', type: :text, column: "#{P}.city" },
      'state' => { group: 'Dados do cliente', label: 'Estado (UF)', type: :text, column: "#{P}.state" },
      'has_email' => { group: 'Dados do cliente', label: 'Tem e-mail', type: :bool, sql: "#{P}.email IS NOT NULL" },
      'has_phone' => { group: 'Dados do cliente', label: 'Tem telefone', type: :bool, sql: "#{P}.phone IS NOT NULL" },
      # Marketing
      'popup' => { group: 'Marketing', label: 'Se cadastrou no pop-up', type: :bool, exists: :popup },
      'email_marketing' => { group: 'Marketing', label: 'Marketing por e-mail', type: :marketing, column: "#{P}.email_marketing_state" },
      'suppressed' => { group: 'Marketing', label: 'Está na lista de recusa de e-mail', type: :bool, exists: :suppressed },
      # Listas/Segmentos
      'segment' => { group: 'Listas/Segmentos', label: 'Faz parte do segmento/lista', type: :segment }
    }.freeze

    MAX_DEPTH = 3

    def initialize(client, rules, depth: 0, exclude_ids: [])
      @client = client
      @rules = rules.is_a?(Hash) ? rules.deep_stringify_keys : {}
      @depth = depth
      @exclude_ids = exclude_ids
      @binds = {}
    end

    # Limpa regras vindas do formulário: só campos/operadores conhecidos.
    def self.sanitize(raw)
      data = raw.is_a?(String) ? (JSON.parse(raw) rescue {}) : raw.to_h # rubocop:disable Style/RescueModifier
      data = data.to_unsafe_h if data.respond_to?(:to_unsafe_h)
      groups = Array(data.deep_stringify_keys['groups']).first(10).filter_map do |group|
        conditions = Array(group.is_a?(Hash) ? group['conditions'] : nil).first(15).filter_map { |c| sanitize_condition(c) }
        { 'conditions' => conditions } if conditions.any?
      end
      { 'groups' => groups }
    end

    def self.sanitize_condition(cond)
      return unless cond.is_a?(Hash)

      field = FIELDS[cond['field'].to_s]
      return unless field && OPS.fetch(field[:type]).key?(cond['op'].to_s)

      value = cond['value']
      value = Array(value).map(&:to_s).first(20) if field[:type].in?(LIST_TYPES)
      { 'field' => cond['field'].to_s, 'op' => cond['op'].to_s,
        'value' => value.is_a?(Array) ? value : value.to_s.strip.first(200),
        'value2' => cond['value2'].to_s.strip.first(200) }
    end

    # Definição exportada para o construtor (JS).
    def self.schema
      {
        categories: [],
        sizes: [],
        fields: FIELDS.map { |key, f| { key:, group: f[:group], label: f[:label], type: f[:type] } },
        ops: OPS.transform_values { |ops| ops.map { |k, l| { key: k, label: l } } },
        rfm: CustomerProfile::RFM_SEGMENTS.map { |k, v| { key: k, label: v[:label] } },
        marketing: MARKETING_STATES.map { |k, label| { key: k, label: } }
      }
    end

    def empty? = groups.empty?

    def groups = Array(@rules['groups'])

    # Relation de CustomerProfile da loja que atende às regras.
    def scope
      base = CustomerProfile.where(client_id: @client.id)
      return base if empty?

      clauses = groups.filter_map { |group| group_sql(group) }
      return base.none if clauses.empty?

      base.where(ActiveRecord::Base.sanitize_sql_array(["(#{clauses.join(') OR (')})", @binds]))
    end

    private

    def group_sql(group)
      items, others = Array(group['conditions']).partition { |cond| FIELDS.dig(cond['field'], :item) }
      parts = others.filter_map { |cond| condition_sql(cond) }
      parts << item_sql(items)
      parts.compact.join(' AND ').presence
    end

    def item_sql(conditions)
      inner = conditions.filter_map { |cond| item_condition_sql(cond) }
      "(EXISTS (#{product_from} AND #{inner.join(' AND ')}))" if inner.any?
    end

    def item_condition_sql(cond)
      case FIELDS.dig(cond['field'], :item)
      when :category then category_sql(cond)
      when :size then size_sql(cond)
      end
    end

    def category_sql(cond)
      values = Array(cond['value']).map { |value| value.to_s.strip.downcase }.compact_blank.first(20)
      return if values.empty?

      "EXISTS (SELECT 1 FROM unnest(string_to_array(p.tags, ',')) AS item_tag WHERE LOWER(BTRIM(item_tag)) IN (#{bind(values)}))"
    end

    def size_sql(cond)
      values = Array(cond['value']).map { |value| value.to_s.strip.upcase }.compact_blank.first(20)
      return if values.empty?

      list = bind(values)
      "(#{%w[option1 option2 option3].map { |column| "UPPER(SPLIT_PART(COALESCE(p.#{column}, ''), '/', 1)) IN (#{list})" }.join(' OR ')})"
    end

    def bind(value)
      key = :"v#{@binds.size}"
      @binds[key] = value
      ":#{key}"
    end

    def condition_sql(cond)
      field = FIELDS[cond['field']]
      return unless field

      sql =
        if field[:type] == :segment then segment_sql(cond)
        elsif field[:sql] then field[:sql]
        elsif field[:exists] then exists_sql(field[:exists], cond)
        else compare(field[:column], field[:type], cond)
        end
      return unless sql

      negated = (field[:type] == :bool && cond['op'] == 'no') || field[:negate]
      negated ? "NOT (#{sql})" : "(#{sql})"
    end

    def compare(column, type, cond)
      case type
      when :number, :money then number_sql(column, cond)
      when :date then date_sql(column, cond)
      when :text then text_sql(column, cond)
      when :rfm then rfm_sql(column, cond)
      when :marketing then marketing_sql(column, cond)
      end
    end

    def number_sql(column, cond)
      value = decimal(cond['value'])
      return if value.nil?

      case cond['op']
      when 'eq' then "#{column} = #{bind(value)}"
      when 'gt' then "#{column} > #{bind(value)}"
      when 'gte' then "#{column} >= #{bind(value)}"
      when 'lt' then "#{column} < #{bind(value)}"
      when 'lte' then "#{column} <= #{bind(value)}"
      when 'between'
        upper = decimal(cond['value2'])
        "#{column} BETWEEN #{bind(value)} AND #{bind(upper)}" if upper
      end
    end

    def date_sql(column, cond)
      case cond['op']
      when 'last_days'
        days = cond['value'].to_i
        "#{column} >= #{bind(days.days.ago.beginning_of_day)}" if days.positive?
      when 'more_than_days'
        days = cond['value'].to_i
        "#{column} < #{bind(days.days.ago.beginning_of_day)}" if days.positive?
      when 'after'
        date = parse_date(cond['value'])
        "#{column} > #{bind(date.end_of_day)}" if date
      when 'before'
        date = parse_date(cond['value'])
        "#{column} < #{bind(date.beginning_of_day)}" if date
      when 'between'
        from = parse_date(cond['value'])
        to = parse_date(cond['value2'])
        "#{column} BETWEEN #{bind(from.beginning_of_day)} AND #{bind(to.end_of_day)}" if from && to
      end
    end

    def text_sql(column, cond)
      value = cond['value'].to_s
      return if value.blank?

      if cond['op'] == 'equals'
        "LOWER(#{column}) = #{bind(value.downcase)}"
      else
        "#{column} ILIKE #{bind("%#{ActiveRecord::Base.sanitize_sql_like(value)}%")}"
      end
    end

    def rfm_sql(column, cond)
      values = Array(cond['value']) & CustomerProfile::RFM_SEGMENTS.keys
      return if values.empty?

      sql = "#{column} IN (#{bind(values)})"
      cond['op'] == 'not_in' ? "(#{column} IS NULL OR NOT #{sql})" : sql
    end

    def marketing_sql(column, cond)
      values = Array(cond['value']) & MARKETING_STATES.keys
      return if values.empty?

      known = values - ['unknown']
      parts = []
      parts << "#{column} IN (#{bind(known)})" if known.any?
      parts << "#{column} IS NULL" if values.include?('unknown')
      matching = "(#{parts.join(' OR ')})"
      cond['op'] == 'not_in' ? "NOT COALESCE(#{matching}, FALSE)" : matching
    end

    ORDERS_OF_CUSTOMER = "SELECT 1 FROM orders o WHERE o.client_id = #{P}.client_id " \
                         "AND o.customer_id = #{P}.customer_id AND o.cancelled_at IS NULL".freeze

    def exists_sql(kind, cond)
      inner =
        case kind
        when :order_date then date_sql('COALESCE(o.shopify_creation_date, o.created_at)', cond)
        when :coupon then text_sql('o.discount_code', cond)
        when :staff then text_sql('o.staff_name', cond)
        when :product, :product_tag then product_sql(kind, cond)
        when :popup
          return "EXISTS (SELECT 1 FROM popup_submissions ps JOIN popups pp ON pp.id = ps.popup_id " \
                 "WHERE pp.client_id = #{P}.client_id AND LOWER(ps.email) = #{P}.email)"
        when :suppressed
          return "EXISTS (SELECT 1 FROM email_suppressions es WHERE es.client_id = #{P}.client_id " \
                 "AND es.email = #{P}.email)"
        end
      return unless inner

      from = kind.in?(%i[product product_tag]) ? product_from : ORDERS_OF_CUSTOMER
      "EXISTS (#{from} AND #{inner})"
    end

    def product_from
      "SELECT 1 FROM orders o JOIN order_items oi ON oi.order_id = o.id LEFT JOIN products p ON p.id = oi.product_id " \
        "WHERE o.client_id = #{P}.client_id AND o.customer_id = #{P}.customer_id AND o.cancelled_at IS NULL"
    end

    def product_sql(kind, cond)
      value = cond['value'].to_s
      return if value.blank?

      like = bind("%#{ActiveRecord::Base.sanitize_sql_like(value)}%")
      kind == :product_tag ? "p.tags ILIKE #{like}" : "(p.shopify_product_name ILIKE #{like} OR oi.sku ILIKE #{like})"
    end

    def segment_sql(cond)
      segment = @client.segments.find_by(id: cond['value'])
      return if segment.nil? || @exclude_ids.include?(segment.id) || @depth >= MAX_DEPTH

      ids_sql = segment.customer_ids_sql(depth: @depth + 1, exclude_ids: @exclude_ids + [segment.id])
      sql = "#{P}.customer_id IN (#{ids_sql})"
      cond['op'] == 'not_in' ? "NOT (#{sql})" : sql
    end

    def decimal(value)
      BigDecimal(value.to_s.tr(',', '.'))
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
