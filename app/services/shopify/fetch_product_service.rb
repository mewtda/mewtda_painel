module Shopify
  class FetchProductService
    REQUEST_TIMEOUT = 10

    def initialize(client)
      @client = client
    end

    def call(handle)
      response = HTTParty.get(product_url(handle), timeout: REQUEST_TIMEOUT)
      return JSON.parse(response.body) if response.success?

      log("#{client.id}/#{handle} respondeu #{response.code}")
    rescue SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError, HTTParty::Error => e
      log("#{client.id}/#{handle} falhou: #{e.class}")
    end

    private

    attr_reader :client

    def product_url(handle)
      host = client.shopify_shop_url.to_s.sub(%r{\Ahttps?://}, '').delete_suffix('/')
      "https://#{host}/products/#{handle}.js"
    end

    def log(message)
      Rails.logger.warn "[Shopify::FetchProductService] #{message}"
      nil
    end
  end
end
