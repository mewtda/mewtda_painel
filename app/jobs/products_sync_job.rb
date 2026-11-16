class ProductsSyncJob < ApplicationJob
  queue_as :default

  API_TRIES = 10

  def perform(action:, client_id:)
    @client = Client.find_by(id: client_id)

    unless @client
      Rails.logger.error "[ProductsSyncJob] Client não encontrado: #{client_id}"
      return
    end

    unless @client.active?
      Rails.logger.error "[ProductsSyncJob] Client inativo: #{@client.name}"
      return
    end

    case action
    when 'sync_all_products'
      sync_all_products
    else
      Rails.logger.error "[ProductsSyncJob] Ação desconhecida: #{action}"
    end
  end

  def client_shopify_rest
    session = ShopifyAPI::Auth::Session.new(
      shop: @client.shopify_shop_url,
      access_token: @client.shopify_access_token
    )

    ShopifyAPI::Clients::Rest::Admin.new(session:)
  end

  def sync_all_products
    Rails.logger.info "[ProductsSyncJob] Iniciando sincronização de produtos para client: #{@client.name}"

    client = client_shopify_rest

    # tries: a Shopify devolve 429 quando outro sync da mesma loja está usando
    # a cota da API REST (2 chamadas/s); o client espera e tenta de novo.
    response = client.get(
      path: 'products',
      query: { limit: 250 },
      tries: API_TRIES
    )

    process_products(response.body['products'])

    loop do
      next_page_info = response.next_page_info
      break unless next_page_info

      response = client.get(
        path: 'products',
        query: {
          limit: 250,
          page_info: next_page_info
        },
        tries: API_TRIES
      )

      process_products(response.body['products'])
    end

    Rails.logger.info "[ProductsSyncJob] Sincronização finalizada para client: #{@client.name}"
  end

  def process_products(products)
    products.each do |shopify_product|
      shopify_product['variants'].each do |variant|
        product = Product.find_or_initialize_by(
          client_id: @client.id,
          shopify_variant_id: variant['id'].to_s
        )

        product.assign_attributes(
          sku: variant['sku'],
          shopify_product_id: shopify_product['id'].to_s,
          shopify_variant_id: variant['id'].to_s,
          shopify_inventory_item_id: variant['inventory_item_id'].to_s,
          shopify_product_name: shopify_product['title'],
          price: variant['price'],
          compare_at_price: variant['compare_at_price'],
          vendor: shopify_product['vendor'],
          option1: variant['option1'],
          option2: variant['option2'],
          option3: variant['option3'],
          tags: shopify_product['tags'],
          image_url: shopify_product.dig('image', 'src')
        )

        product.save!

        Rails.logger.info "[ProductsSyncJob] Produto sincronizado SKU #{product.sku} para client: #{@client.name}"
      end
    end
  end
end
