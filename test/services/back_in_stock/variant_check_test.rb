require 'test_helper'

class BackInStock::VariantCheckTest < ActiveSupport::TestCase
  Result = Shopify::FetchProductService::Result

  class FakeFetcher
    attr_reader :calls

    def initialize(result)
      @result = result
      @calls = 0
    end

    def lookup(_handle)
      @calls += 1
      @result
    end
  end

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", shopify_shop_url: 'loja.myshopify.com')
    @product = { 'id' => 10, 'variants' => [{ 'id' => 101 }, { 'id' => 102 }] }
  end

  def check(result, **args)
    BackInStock::VariantCheck.new(@client, fetcher: FakeFetcher.new(result))
                             .call(handle: 'vestido', product_id: '10', variant_id: '101', **args)
  end

  test 'accepts a variant that belongs to the product' do
    assert_equal :ok, check(Result.new(:found, @product))
  end

  test 'rejects an invented variant or product id' do
    assert_equal :unknown, check(Result.new(:found, @product), variant_id: '999')
    assert_equal :unknown, check(Result.new(:found, @product), product_id: '11')
  end

  test 'rejects a product the store does not have' do
    assert_equal :unknown, check(Result.new(:missing, nil))
  end

  test 'reports when Shopify is throttling and when the store did not answer' do
    assert_equal :throttled, check(Result.new(:throttled, nil))
    assert_equal :error, check(Result.new(:error, nil))
  end

  test 'rejects a malformed handle without calling the store' do
    fetcher = FakeFetcher.new(Result.new(:found, @product))
    result = BackInStock::VariantCheck.new(@client, fetcher:).call(handle: '../admin', product_id: 10, variant_id: 101)
    assert_equal :unknown, result
    assert_equal 0, fetcher.calls
  end
end
