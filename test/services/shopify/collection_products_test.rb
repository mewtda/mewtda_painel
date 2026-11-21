require 'test_helper'

class Shopify::CollectionProductsTest < ActiveSupport::TestCase
  class FakeShopify
    attr_reader :last_query

    def initialize(data) = @data = data

    def query(graphql)
      @last_query = graphql
      @data
    end
  end

  setup do
    @client = Client.create!(name: 'OneWay', email: "loja-#{SecureRandom.hex(4)}@example.com", site_url: 'https://lojaoneway.com/')
  end

  def node(title, status: 'ACTIVE', available: true, image: 'https://cdn.shopify.com/a.jpg', amount: '599.0')
    { 'title' => title, 'handle' => title.parameterize, 'status' => status,
      'featuredImage' => image && { 'url' => image }, 'priceRangeV2' => { 'minVariantPrice' => { 'amount' => amount } },
      'variants' => { 'nodes' => [{ 'availableForSale' => available }] } }
  end

  test 'products of a collection: active and in stock, with price, photo and store link' do
    data = { 'collectionByHandle' => { 'products' => { 'nodes' => [
      node('Vestido Longo'), node('Esgotado', available: false), node('Rascunho', status: 'DRAFT'),
      node('Calça Reta', amount: '1209.9'), node('Sem foto', image: nil)
    ] } } }
    fake = FakeShopify.new(data)

    products = Shopify::CollectionProducts.new(@client, shopify: fake).products('novidades', limit: 6)

    assert_match '"novidades"', fake.last_query
    assert_equal ['Vestido Longo', 'Calça Reta', 'Sem foto'], products.map { |p| p[:title] }
    assert_equal 'R$ 599,00', products.first[:price]
    assert_equal 'R$ 1.209,90', products.second[:price]
    assert_equal 'https://lojaoneway.com/products/vestido-longo', products.first[:link]
    assert_equal '', products.last[:photo]
  end

  test 'respects the limit and lists collections' do
    data = { 'collectionByHandle' => { 'products' => { 'nodes' => (1..5).map { |i| node("P#{i}") } } } }
    assert_equal 3, Shopify::CollectionProducts.new(@client, shopify: FakeShopify.new(data)).products('x', limit: 3).size

    list = { 'collections' => { 'nodes' => [{ 'handle' => 'novidades', 'title' => 'Novidades', 'productsCount' => { 'count' => 42 } }] } }
    assert_equal [{ handle: 'novidades', title: 'Novidades', count: 42 }],
                 Shopify::CollectionProducts.new(@client, shopify: FakeShopify.new(list)).collections
  end
end
