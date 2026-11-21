require 'test_helper'

class BackInStock::NotifyMeImportTest < ActiveSupport::TestCase
  CSV_TEXT = <<~CSV.freeze
    id,status,subscribe_at,created_at,product_id,variant_id,sku,email,phone_number,whatsapp_number,locale,quantity
    1,WAITING_RESTOCK,2026-05-10T10:00:00Z,2026-05-10T10:00:00Z,10,101,VEST-P,Ana@Example.com,,+5516992375432,pt,1
    2,WAITING_RESTOCK,2026-06-01T10:00:00Z,2026-06-01T10:00:00Z,10,102,VEST-M,bia@example.com,+5516990000000,,pt,1
    3,WAITING_RESTOCK,2026-06-02T10:00:00Z,2026-06-02T10:00:00Z,10,103,VEST-G,caio@example.com,,,pt,1
    4,WAITING_RESTOCK,2026-06-03T10:00:00Z,2026-06-03T10:00:00Z,10,101,VEST-P,,,+5516991111111,pt,1
    5,WAITING_RESTOCK,2026-06-04T10:00:00Z,2026-06-04T10:00:00Z,10,,,dani@example.com,,,pt,1
    6,WAITING_RESTOCK,2026-06-05T10:00:00Z,2026-06-05T10:00:00Z,10,999,X,edu@example.com,,,pt,1
  CSV

  class FakeShopify
    attr_reader :queries

    def initialize
      @queries = 0
    end

    def query(_graphql)
      @queries += 1
      product = { 'legacyResourceId' => '10', 'handle' => 'vestido-longo', 'title' => 'Vestido Longo',
                  'featuredImage' => { 'url' => 'https://cdn.shopify.com/v.jpg' } }
      { 'nodes' => [
        { 'legacyResourceId' => '101', 'title' => 'P', 'sku' => 'VEST-P', 'price' => '599.00', 'availableForSale' => false,
          'image' => nil, 'product' => product },
        { 'legacyResourceId' => '102', 'title' => 'M', 'sku' => 'VEST-M', 'price' => '599.00', 'availableForSale' => false,
          'image' => { 'url' => 'https://cdn.shopify.com/m.jpg' }, 'product' => product },
        { 'legacyResourceId' => '103', 'title' => 'G', 'sku' => 'VEST-G', 'price' => '599.00', 'availableForSale' => true,
          'image' => nil, 'product' => product },
        nil
      ] }
    end
  end

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def run_import(**opts)
    BackInStock::NotifyMeImport.new(@client, shopify: FakeShopify.new, **opts).call(CSV_TEXT)
  end

  test 'dry run counts everything and writes nothing' do
    result = run_import

    assert_equal 6, result.rows
    assert_equal 1, result.without_email
    assert_equal 1, result.without_variant
    assert_equal 1, result.variant_missing
    assert_equal 1, result.available_now
    assert_equal 2, result.importable
    assert_equal 0, result.created
    assert_equal 0, @client.back_in_stock_alerts.count
  end

  test 'imports pending alerts with Shopify product data, keeping the original request date' do
    result = run_import(dry_run: false)

    assert_equal 2, result.created
    ana = @client.back_in_stock_alerts.find_by!(email: 'ana@example.com')
    assert ana.pending?
    assert_equal [10, 101, 'vestido-longo', 'Vestido Longo', 'P', 'VEST-P'],
                 [ana.shopify_product_id, ana.shopify_variant_id, ana.product_handle, ana.product_title, ana.variant_title, ana.sku]
    assert_equal 'https://cdn.shopify.com/v.jpg', ana.image_url
    assert_equal '+5516992375432', ana.phone
    assert_equal Time.zone.parse('2026-05-10T10:00:00Z'), ana.created_at
    assert_equal Time.zone.parse('2026-05-10T10:00:00Z'), ana.consented_at
    assert_nil @client.back_in_stock_alerts.find_by(email: 'caio@example.com'), 'variante com estoque fica de fora'
  end

  test 'running again does not duplicate, and available variants come in only when asked' do
    run_import(dry_run: false)
    again = run_import(dry_run: false, include_available: true)

    assert_equal 2, again.already_pending
    assert_equal 1, again.created
    assert_equal 3, @client.back_in_stock_alerts.pending.count
  end
end
