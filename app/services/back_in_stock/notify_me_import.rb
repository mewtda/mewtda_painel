require 'csv'

module BackInStock
  # Migração do app Notify Me!: importa as solicitações pendentes (CSV gerado da API pública do Notify Me,
  # uma linha por pessoa e variante) como alertas pendentes de "De volta ao estoque".
  #
  # Os dados do produto (handle, título, variante, SKU, preço, imagem) vêm da Shopify, porque o alerta
  # precisa do handle para a checagem de reposição. Linhas sem e-mail, sem variante ou com variante que
  # não existe mais na loja ficam de fora e são contadas no resultado.
  #
  # Atenção: a checagem de reposição avisa na hora todo alerta pendente cuja variante esteja disponível.
  # Por isso, as variantes que já estão com estoque só entram com include_available: true.
  #
  # dry_run: true (padrão) não grava nada e só devolve as contagens.
  class NotifyMeImport
    BATCH = 100
    Result = Struct.new(:rows, :without_email, :without_variant, :variant_missing, :available_now, :importable,
                        :created, :already_pending, :failed, keyword_init: true)

    def initialize(client, dry_run: true, include_available: false, shopify: nil)
      @client = client
      @dry_run = dry_run
      @include_available = include_available
      @shopify = shopify
    end

    def call(csv_text)
      rows = CSV.parse(csv_text.to_s, headers: true).map(&:to_h)
      result = Result.new(rows: rows.size, without_email: 0, without_variant: 0, variant_missing: 0, available_now: 0,
                          importable: 0, created: 0, already_pending: 0, failed: 0)
      candidates = rows.select do |row|
        if row['email'].to_s.strip.empty?
          result.without_email += 1
          next false
        end
        if row['variant_id'].to_s.strip.empty?
          result.without_variant += 1
          next false
        end
        true
      end
      variants = fetch_variants(candidates.map { |row| row['variant_id'].to_s.strip }.uniq)

      candidates.each do |row|
        variant = variants[row['variant_id'].to_s.strip]
        next result.variant_missing += 1 unless variant

        if variant[:available]
          result.available_now += 1
          next unless @include_available
        end

        result.importable += 1
        import(row, variant, result) unless @dry_run
      end
      result
    end

    private

    def shopify = @shopify ||= Shopify::Client.new(@client)

    def import(row, variant, result)
      email = row['email'].to_s.strip.downcase
      if @client.back_in_stock_alerts.pending.exists?(shopify_variant_id: variant[:variant_id], email:)
        return result.already_pending += 1
      end

      requested_at = parse_time(row['subscribe_at']) || parse_time(row['created_at']) || Time.current
      alert = @client.back_in_stock_alerts.new(
        variant.except(:available).merge(email:, phone: row['whatsapp_number'].presence || row['phone_number'].presence,
                                         consented_at: requested_at, created_at: requested_at)
      )
      alert.save ? result.created += 1 : result.failed += 1
    rescue ActiveRecord::RecordNotUnique
      result.already_pending += 1
    end

    # { "123" => { shopify_product_id:, shopify_variant_id:, product_handle:, ..., available: } }
    def fetch_variants(ids)
      ids.each_slice(BATCH).each_with_object({}) do |slice, found|
        gids = slice.map { |id| "gid://shopify/ProductVariant/#{id}" }
        data = shopify.query(<<~GRAPHQL)
          {
            nodes(ids: #{gids.to_json}) {
              ... on ProductVariant {
                id legacyResourceId title sku price availableForSale
                image { url }
                product { legacyResourceId handle title featuredImage { url } }
              }
            }
          }
        GRAPHQL
        Array(data['nodes']).compact.each do |node|
          next unless node['product']

          found[node['legacyResourceId'].to_s] = variant_attributes(node)
        end
      end
    end

    def variant_attributes(node)
      product = node['product']
      title = node['title'] == RestockCheckJob::DEFAULT_VARIANT_TITLE ? nil : node['title']
      image = node.dig('image', 'url') || product.dig('featuredImage', 'url')
      {
        shopify_product_id: product['legacyResourceId'].to_i, shopify_variant_id: node['legacyResourceId'].to_i,
        product_handle: product['handle'], product_title: product['title'].to_s.first(255),
        variant_title: title&.first(255), sku: node['sku'].presence&.first(255), price: node['price'],
        image_url: (image if image.to_s.start_with?('https://')), available: node['availableForSale'] == true
      }
    end

    def parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
