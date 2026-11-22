module BackInStock
  # Confere, antes de aceitar um pedido de aviso, se o produto e a variação existem mesmo na loja.
  # Sem isso, um script pode cadastrar milhares de produtos inventados, que ficam pendentes para sempre
  # e deixam a checagem de estoque lenta. A resposta da loja fica em cache: vários pedidos do mesmo
  # produto não viram várias consultas.
  class VariantCheck
    FOUND_TTL = 10.minutes
    MISSING_TTL = 2.minutes
    TIMEOUT = 4

    def initialize(client, fetcher: nil)
      @client = client
      @fetcher = fetcher || Shopify::FetchProductService.new(client, timeout: TIMEOUT)
    end

    # true: existe; false: não existe; nil: a loja não respondeu (quem chama decide).
    def valid?(handle:, product_id:, variant_id:)
      return false unless handle.to_s.match?(/\A[a-z0-9-]{1,255}\z/)

      info = product_info(handle)
      return if info.nil?
      return false if info['missing']

      info['id'].to_s == product_id.to_s && info['variant_ids'].map(&:to_s).include?(variant_id.to_s)
    end

    private

    def product_info(handle)
      key = ['bis_variant_check', @client.id, handle]
      cached = Rails.cache.read(key)
      return cached if cached

      result = @fetcher.lookup(handle)
      info = if result.found?
               { 'id' => result.product['id'], 'variant_ids' => Array(result.product['variants']).pluck('id') }
             elsif result.missing?
               { 'missing' => true }
             end
      Rails.cache.write(key, info, expires_in: info['missing'] ? MISSING_TTL : FOUND_TTL) if info
      info
    end
  end
end
