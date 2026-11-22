require 'test_helper'

class Shopify::ProductsByIdsTest < ActiveSupport::TestCase
  class FakeShopify
    attr_reader :queries

    def initialize(nodes_per_query)
      @nodes_per_query = nodes_per_query
      @queries = []
    end

    def query(graphql)
      @queries << graphql
      { 'nodes' => @nodes_per_query.shift }
    end
  end

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def node(id, status: 'ACTIVE', url: 'https://loja.com/products/x')
    { 'legacyResourceId' => id.to_s, 'handle' => "produto-#{id}", 'title' => 'Vestido', 'status' => status,
      'onlineStoreUrl' => url, 'featuredImage' => { 'url' => 'https://cdn.shopify.com/p.jpg' },
      'variants' => { 'nodes' => [{ 'legacyResourceId' => '101', 'title' => 'M', 'availableForSale' => true,
                                    'image' => nil }] } }
  end

  test 'maps products by id in the same shape as the storefront product json' do
    shopify = FakeShopify.new([[node(10), nil, node(12, status: 'DRAFT', url: nil)]])
    result = Shopify::ProductsByIds.new(@client, shopify:).call([10, 11, 12])

    assert_equal 'produto-10', result[10]['handle']
    assert result[10]['live']
    assert_equal [{ 'id' => 101, 'title' => 'M', 'available' => true, 'featured_image' => nil }], result[10]['variants']
    assert result.key?(11)
    assert_nil result[11]
    refute result[12]['live']
  end

  test 'queries in batches' do
    ids = (1..20).to_a
    shopify = FakeShopify.new([ids.first(15).map { |id| node(id) }, ids.last(5).map { |id| node(id) }])
    result = Shopify::ProductsByIds.new(@client, shopify:).call(ids)

    assert_equal 2, shopify.queries.size
    assert_equal ids, result.keys
  end
end
