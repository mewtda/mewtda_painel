module Shopify
  # Produtos pelo id via Admin API, em lotes: a checagem de estoque usa isto em vez da página pública
  # do produto, que a Shopify limita (429) quando consultamos muitos produtos seguidos.
  # Devolve { id => produto | nil }; nil = o produto não existe mais na loja.
  class ProductsByIds
    BATCH_SIZE = 15 # mantém o custo estimado da consulta abaixo do teto de 1000 pontos
    VARIANTS_LIMIT = 50

    def initialize(client, shopify: nil)
      @client = client
      @shopify = shopify
    end

    def call(ids)
      ids.map(&:to_i).uniq.each_slice(BATCH_SIZE).each_with_object({}) do |batch, found|
        nodes = Array(shopify.query(query(batch))['nodes'])
        batch.each_with_index { |id, index| found[id] = normalize(nodes[index]) }
      end
    end

    private

    def shopify = @shopify ||= Shopify::Client.new(@client)

    def query(ids)
      gids = ids.map { |id| "gid://shopify/Product/#{id}" }
      <<~GRAPHQL
        {
          nodes(ids: #{gids.to_json}) {
            ... on Product {
              legacyResourceId handle title status onlineStoreUrl
              featuredImage { url }
              variants(first: #{VARIANTS_LIMIT}) { nodes { legacyResourceId title availableForSale image { url } } }
            }
          }
        }
      GRAPHQL
    end

    # Mesmo formato do /products/<handle>.js, que o resto do fluxo já conhece.
    def normalize(node)
      return if node.nil? || node['legacyResourceId'].blank?

      {
        'id' => node['legacyResourceId'].to_i,
        'handle' => node['handle'],
        'title' => node['title'],
        'live' => node['status'] == 'ACTIVE' && node['onlineStoreUrl'].present?,
        'featured_image' => node.dig('featuredImage', 'url'),
        'variants' => Array(node.dig('variants', 'nodes')).map { |variant| normalize_variant(variant) }
      }
    end

    def normalize_variant(variant)
      {
        'id' => variant['legacyResourceId'].to_i,
        'title' => variant['title'],
        'available' => variant['availableForSale'] == true,
        'featured_image' => ({ 'src' => variant.dig('image', 'url') } if variant.dig('image', 'url'))
      }
    end
  end
end
