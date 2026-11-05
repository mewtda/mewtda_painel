module Sales
  # Vendas por tag direto do relatório da Shopify (ShopifyQL), para a meta por
  # tag bater com o que a loja mostra: "vendas totais" com descontos, devoluções,
  # frete e impostos, no fuso de São Paulo. Requer read_reports na app da loja.
  class ShopifyTaggedSales
    API_VERSION = '2025-10'.freeze
    CACHE_TTL = 15.minutes
    QUERY = 'query($q: String!) { shopifyqlQuery(query: $q) { tableData { rows } parseErrors } }'.freeze
    TAG_FORMAT = /\A[\p{L}\p{N} _-]+\z/

    def initialize(client:, from:, to:, tags:, runner: nil)
      @client = client
      @from = from.to_date
      @to = to.to_date
      @tags = expand(tags)
      @runner = runner
    end

    # => BigDecimal com o total das tags no período, ou nil se não der para consultar.
    def total
      return nil if @tags.empty? || !@client.shopify_configured?

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch_total }
    rescue StandardError => e
      Rails.logger.warn("[ShopifyTaggedSales] client #{@client.id}: #{e.class}")
      nil
    end

    def shopifyql
      conditions = @tags.map { |t| "order_tags CONTAINS '#{t}'" }.join(' OR ')
      list = @tags.map { |t| "'#{t}'" }.join(', ')
      "FROM sales SHOW total_sales, orders WHERE #{conditions} GROUP BY order_tag WITH TOTALS, " \
        "TIMEZONE 'America/Sao_Paulo', CURRENCY 'BRL' HAVING order_tag IN (#{list}) " \
        "SINCE #{@from.iso8601} UNTIL #{@to.iso8601}"
    end

    private

    def expand(value)
      tags = value.to_s.split(',').map(&:strip).reject(&:blank?)
      tags = tags.flat_map { |t| Order::TAG_GROUPS.find { |g| g.any? { |a| a.casecmp?(t) } } || [t] }
      tags.uniq(&:downcase).select { |t| t.match?(TAG_FORMAT) }
    end

    def cache_key
      ['shopify_tagged_sales', @client.id, @from, @to, @tags.map(&:downcase).sort.join('|')].join(':')
    end

    def fetch_total
      body = run(shopifyql)
      data = body.dig('data', 'shopifyqlQuery')
      raise ArgumentError, 'shopifyql_failed' if body['errors'].present? || data.nil? || data['parseErrors'].present?

      rows = data.dig('tableData', 'rows') || []
      # Linhas vazias = nenhum pedido com as tags no período.
      return BigDecimal('0') if rows.empty?

      BigDecimal(rows.first['total_sales__totals'].to_s)
    end

    def run(query)
      return @runner.call(query) if @runner

      session = ShopifyAPI::Auth::Session.new(shop: @client.shopify_shop_url, access_token: @client.shopify_access_token)
      ShopifyAPI::Clients::Graphql::Admin.new(session: session, api_version: API_VERSION)
                                         .query(query: QUERY, variables: { q: query }).body
    end
  end
end
