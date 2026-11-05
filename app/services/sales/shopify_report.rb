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
