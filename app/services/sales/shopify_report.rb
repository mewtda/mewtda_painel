module Sales
  # Roda consultas ShopifyQL (relatórios da Shopify) da loja do cliente.
  # Os números saem iguais aos relatórios do admin da Shopify. Requer a
  # permissão read_reports na app da loja. Falhas viram nil: quem chama decide
  # o cálculo de reserva.
  class ShopifyReport
    API_VERSION = '2025-10'.freeze
    CACHE_TTL = 15.minutes
    GRAPHQL = 'query($q: String!) { shopifyqlQuery(query: $q) { tableData { rows } parseErrors } }'.freeze
    TAG_FORMAT = /\A[\p{L}\p{N} _-]+\z/

    def initialize(client:, runner: nil)
      @client = client
      @runner = runner
    end

    # Linhas do resultado (Array de Hash com strings), ou nil se não deu para consultar.
    def rows(shopifyql)
      return nil unless @client.shopify_configured?

      Rails.cache.fetch(['shopify_report', @client.id, Digest::SHA256.hexdigest(shopifyql)].join(':'),
                        expires_in: CACHE_TTL) { fetch(shopifyql) }
    rescue StandardError => e
      Rails.logger.warn("[ShopifyReport] client #{@client.id}: #{e.class}")
      nil
    end

    WITH_OPTIONS = "TIMEZONE 'America/Sao_Paulo', CURRENCY 'BRL'".freeze

    def self.range(from, to)
      "SINCE #{from.to_date.iso8601} UNTIL #{to.to_date.iso8601}"
    end

    # Tags da meta/filtro, com os grupos de Order::TAG_GROUPS e só caracteres
    # seguros para entrar na consulta.
    def self.tags(value)
      tags = value.to_s.split(',').map(&:strip).reject(&:blank?)
      tags = tags.flat_map { |t| Order::TAG_GROUPS.find { |g| g.any? { |a| a.casecmp?(t) } } || [t] }
      tags.uniq(&:downcase).select { |t| t.match?(TAG_FORMAT) }
    end

    def self.tag_condition(tags)
      tags.map { |t| "order_tags CONTAINS '#{t}'" }.join(' OR ')
    end

    LOCATION_FORMAT = /\A[\p{L}\p{N} ._&()\/-]+\z/
    # Pedidos sem location de PDV (loja online, pedidos preliminares...).
    NO_LOCATION = 'Sem location (loja online)'.freeze

    # Filtro das locations escolhidas na configuração do cliente (nil = todas).
    def self.location_condition(locations)
      list = Array(locations).map(&:to_s).uniq
      named = list.select { |l| l != NO_LOCATION && l.match?(LOCATION_FORMAT) }
      conditions = []
      conditions << "pos_location_name IN (#{named.map { |l| "'#{l}'" }.join(', ')})" if named.any?
      conditions << 'pos_location_name IS NULL' if list.include?(NO_LOCATION)
      return if conditions.empty?

      conditions.join(' OR ')
    end

    # "WHERE (a) AND (b) " com as condições que existirem, ou "".
    def self.where(*conditions)
      conditions = conditions.compact_blank
      return '' if conditions.empty?

      return "WHERE #{conditions.first} " if conditions.one?

      "WHERE #{conditions.map { |c| "(#{c})" }.join(' AND ')} "
    end

    # Locations com pedidos no último ano, da que mais vende pra que menos vende.
    # Pedidos sem location aparecem como NO_LOCATION.
    def sales_locations
      rows("FROM sales SHOW orders GROUP BY pos_location_name WITH #{WITH_OPTIONS} SINCE -365d UNTIL today")
        &.sort_by { |row| -row['orders'].to_i }
        &.map { |row| row['pos_location_name'].presence || NO_LOCATION }
        &.uniq
    end

    private

    def fetch(shopifyql)
      body = run(shopifyql)
      data = body.dig('data', 'shopifyqlQuery')
      raise ArgumentError, 'shopifyql_failed' if body['errors'].present? || data.nil? || data['parseErrors'].present?

      data.dig('tableData', 'rows') || []
    end

    def run(shopifyql)
      return @runner.call(shopifyql) if @runner

      session = ShopifyAPI::Auth::Session.new(shop: @client.shopify_shop_url, access_token: @client.shopify_access_token)
      ShopifyAPI::Clients::Graphql::Admin.new(session: session, api_version: API_VERSION)
                                         .query(query: GRAPHQL, variables: { q: shopifyql }).body
    end
  end
end
