require 'test_helper'

class BackInStock::RestockCheckJobTest < ActiveSupport::TestCase
  class FakeProducts
    attr_reader :ids

    def initialize(products)
      @products = products
      @ids = []
    end

    def call(ids)
      @ids.concat(ids)
      ids.select { |id| @products.key?(id) }.index_with { |id| @products[id] }
    end
  end

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             shopify_shop_url: 'loja.myshopify.com', site_url: 'https://loja.com',
                             email_sending_domain: 'loja.com', ses_verification_status: 'verified')
    template = EmailTemplate.create!(client: @client, name: 'Aviso', subject: 'Voltou!',
                                     blocks: [{ 'type' => 'heading', 'text' => 'Oi' }])
    BackInStockSetting.create!(client: @client, email_template: template)
    @notified = []
  end

  def alert!(handle: 'vestido', product_id: 10, variant_id: 101)
    @client.back_in_stock_alerts.create!(shopify_product_id: product_id, shopify_variant_id: variant_id,
                                         product_handle: handle, email: "c-#{SecureRandom.hex(3)}@example.com")
  end

  def run_job(products)
    fake = FakeProducts.new(products)
    Shopify::ProductsByIds.stub(:new, ->(*) { fake }) do
      BackInStock::NotifyJob.stub(:perform_now, ->(id, _snapshot) { @notified << id }) do
        BackInStock::RestockCheckJob.perform_now
      end
    end
    fake
  end

  def product(available: true, handle: 'vestido', live: true)
    { 'id' => 10, 'handle' => handle, 'title' => 'Vestido', 'live' => live,
      'variants' => [{ 'id' => 101, 'title' => 'M', 'available' => available }] }
  end

  test 'notifies when the variant is back and marks the product as checked' do
    alert = alert!
    run_job({ 10 => product })
    assert_equal [alert.id], @notified
    assert alert.reload.checked_at.present?
  end

  test 'does not notify while still sold out' do
    alert!
    run_job({ 10 => product(available: false) })
    assert_empty @notified
  end

  test 'cancels alerts for a product deleted from the store' do
    alert = alert!
    run_job({ 10 => nil })
    assert alert.reload.cancelled?
  end

  test 'keeps waiting without notifying while the product is a draft / off the store' do
    alert = alert!
    run_job({ 10 => product(live: false) })
    assert alert.reload.pending?
    assert_empty @notified
  end

  test 'follows a product whose link (handle) changed' do
    alert = alert!
    run_job({ 10 => product(available: false, handle: 'vestido-novo') })
    assert_equal 'vestido-novo', alert.reload.product_handle
    assert alert.pending?
  end

  test 'cancels alerts for a variant removed from the product' do
    alert = alert!(variant_id: 999)
    run_job({ 10 => product })
    assert alert.reload.cancelled?
  end

  test 'keeps alerts when Shopify did not return the product' do
    alert = alert!
    run_job({})
    assert alert.reload.pending?
    assert_nil alert.checked_at
  end

  test 'checks at most a fixed number of products per store, least recently checked first' do
    alert!(product_id: 1, variant_id: 1).update_columns(checked_at: 1.hour.ago)
    alert!(product_id: 2, variant_id: 2)
    alert!(product_id: 3, variant_id: 3).update_columns(checked_at: 1.minute.ago)

    fake = nil
    with_max_products(2) { fake = run_job({}) }
    assert_equal [2, 1], fake.ids
  end

  test 'skips the run when the previous one is still going' do
    alert!
    key = BackInStock::RestockCheckJob::LOCK_KEY
    # Nos testes o pool devolve sempre a mesma conexão; a "rodada anterior" precisa de uma sessão própria.
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    other = PG.connect(dbname: config[:database], host: config[:host], port: config[:port],
                       user: config[:username], password: config[:password])
    begin
      assert_equal 't', other.exec("SELECT pg_try_advisory_lock(#{key})").getvalue(0, 0)
      fake = run_job({ 10 => product })
      assert_empty fake.ids
      assert_empty @notified
    ensure
      other.close
    end
  end

  private

  def with_max_products(value)
    original = BackInStock::RestockCheckJob::MAX_PRODUCTS_PER_CLIENT
    BackInStock::RestockCheckJob.send(:remove_const, :MAX_PRODUCTS_PER_CLIENT)
    BackInStock::RestockCheckJob.const_set(:MAX_PRODUCTS_PER_CLIENT, value)
    yield
  ensure
    BackInStock::RestockCheckJob.send(:remove_const, :MAX_PRODUCTS_PER_CLIENT)
    BackInStock::RestockCheckJob.const_set(:MAX_PRODUCTS_PER_CLIENT, original)
  end
end
