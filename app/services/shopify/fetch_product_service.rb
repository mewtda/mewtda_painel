module Shopify
  # Lê o produto pela página pública da loja (/products/<handle>.js), o mesmo dado que o site usa.
  class FetchProductService
    REQUEST_TIMEOUT = 10

    # found: produto existe e está publicado; missing: a loja respondeu 404;
    # throttled: a Shopify limitou as consultas (429); error: não deu pra saber.
    Result = Struct.new(:status, :product) do
      def found? = status == :found
      def missing? = status == :missing
    end

    def initialize(client, timeout: REQUEST_TIMEOUT)
      @client = client
      @timeout = timeout
    end

    def call(handle)
      lookup(handle).product
    end

    def lookup(handle)
      response = HTTParty.get(product_url(handle), timeout: @timeout)
      return Result.new(:found, JSON.parse(response.body)) if response.success?

      log("#{client.id}/#{handle} respondeu #{response.code}")
      Result.new({ 404 => :missing, 429 => :throttled }.fetch(response.code, :error), nil)
    rescue SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError, HTTParty::Error => e
      log("#{client.id}/#{handle} falhou: #{e.class}")
      Result.new(:error, nil)
    end

    private

    attr_reader :client

    def product_url(handle)
      host = client.shopify_shop_url.to_s.sub(%r{\Ahttps?://}, '').delete_suffix('/')
      "https://#{host}/products/#{ERB::Util.url_encode(handle)}.js"
    end

    def log(message)
      Rails.logger.warn "[Shopify::FetchProductService] #{message}"
      nil
    end
  end
end
