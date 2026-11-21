module Shopify
  # Coleções da loja e produtos de uma coleção, para o bloco "Produtos da loja" do editor de e-mail.
  # Devolve só o que o e-mail precisa: nome, preço formatado, foto (https) e link da página do produto.
  class CollectionProducts
    COLLECTIONS_LIMIT = 100
    PRODUCTS_LIMIT = 24

    def initialize(client, shopify: nil)
      @client = client
      @shopify = shopify
    end

    def collections
      data = shopify.query(<<~GRAPHQL)
        { collections(first: #{COLLECTIONS_LIMIT}, sortKey: TITLE) { nodes { handle title productsCount { count } } } }
      GRAPHQL
      Array(data.dig('collections', 'nodes')).map do |node|
        { handle: node['handle'], title: node['title'], count: node.dig('productsCount', 'count').to_i }
      end
    end

    # Produtos da coleção na ordem da coleção; esgotados ficam de fora (não faz sentido oferecer no e-mail).
    def products(handle, limit: 9)
      data = shopify.query(<<~GRAPHQL)
        {
          collectionByHandle(handle: #{handle.to_s.to_json}) {
            title
            products(first: #{PRODUCTS_LIMIT}, sortKey: COLLECTION_DEFAULT) {
              nodes {
                title handle status totalInventory
                featuredImage { url(transform: { maxWidth: 600 }) }
                priceRangeV2 { minVariantPrice { amount } }
                variants(first: 50) { nodes { availableForSale } }
              }
            }
          }
        }
      GRAPHQL
      nodes = Array(data.dig('collectionByHandle', 'products', 'nodes'))
      nodes.select { |node| node['status'] == 'ACTIVE' && available?(node) }
           .first(limit.to_i.clamp(1, 9))
           .map { |node| item(node) }
    end

    private

    def shopify = @shopify ||= Shopify::Client.new(@client)

    def available?(node)
      Array(node.dig('variants', 'nodes')).any? { |variant| variant['availableForSale'] }
    end

    def item(node)
      photo = node.dig('featuredImage', 'url').to_s
      {
        title: node['title'].to_s.first(120),
        price: price(node.dig('priceRangeV2', 'minVariantPrice', 'amount')),
        photo: (photo if photo.start_with?('https://')).to_s,
        link: "#{@client.storefront_url}/products/#{node['handle']}"
      }
    end

    def price(amount)
      return '' if amount.blank?

      ActiveSupport::NumberHelper.number_to_currency(amount.to_d, unit: 'R$', separator: ',', delimiter: '.')
    end
  end
end
