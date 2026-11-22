require 'test_helper'

class BackInStock::RestockCheckJobTest < ActiveSupport::TestCase
  Result = Shopify::FetchProductService::Result

  class FakeFetcher
    attr_reader :handles

    def initialize(results)
      @results = results
      @handles = []
    end

    def lookup(handle)
      @handles << handle
      @results.fetch(handle) { Result.new(:error, nil) }
    end
  end

  class FakeAdmin
    def initialize(nodes) = @nodes = nodes
    def query(_graphql) = { 'nodes' => @nodes }
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

  def run_job(results, admin_nodes: [])
    fetcher = FakeFetcher.new(results)
    Shopify::FetchProductService.stub(:new, fetcher) do
      Shopify::Client.stub(:new, FakeAdmin.new(admin_nodes)) do
        BackInStock::NotifyJob.stub(:perform_now, ->(id, _snapshot) { @notified << id }) do
          BackInStock::RestockCheckJob.perform_now
        end
      end
    end
    fetcher
  end

  def product(available: true)
    { 'id' => 10, 'title' => 'Vestido', 'variants' => [{ 'id' => 101, 'title' => 'M', 'available' => available }] }
  end

  test 'notifies when the variant is back and marks the product as checked' do
    alert = alert!
    run_job({ 'vestido' => Result.new(:found, product) })
    assert_equal [alert.id], @notified
    assert alert.reload.checked_at.present?
  end

  test 'does not notify while still sold out' do
    alert!
    run_job({ 'vestido' => Result.new(:found, product(available: false)) })
    assert_empty @notified
  end

  test 'cancels alerts for a product deleted from the store' do
    alert = alert!(handle: 'inventado')
    run_job({ 'inventado' => Result.new(:missing, nil) }, admin_nodes: [nil])
    assert alert.reload.cancelled?
  end

  test 'keeps waiting when the product is only unpublished (draft)' do
    alert = alert!
    run_job({ 'vestido' => Result.new(:missing, nil) }, admin_nodes: [{ 'handle' => 'vestido' }])
    assert alert.reload.pending?
  end

  test 'follows a product whose link (handle) changed' do
    alert = alert!
    run_job({ 'vestido' => Result.new(:missing, nil) }, admin_nodes: [{ 'handle' => 'vestido-novo' }])
    assert_equal 'vestido-novo', alert.reload.product_handle
    assert alert.pending?
  end

  test 'keeps alerts when the store could not be reached' do
    alert = alert!
    run_job({}, admin_nodes: [nil])
    assert alert.reload.pending?
  end

  test 'checks at most a fixed number of products per store, least recently checked first' do
    old = alert!(handle: 'antigo', variant_id: 1)
    old.update_columns(checked_at: 1.hour.ago)
    alert!(handle: 'novo', variant_id: 2)
    alert!(handle: 'recente', variant_id: 3).update_columns(checked_at: 1.minute.ago)

    fetcher = nil
    with_max_handles(2) { fetcher = run_job({}) }
    assert_equal %w[novo antigo], fetcher.handles
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
      fetcher = run_job({ 'vestido' => Result.new(:found, product) })
      assert_empty fetcher.handles
      assert_empty @notified
    ensure
      other.close
    end
  end

  private

  def with_max_handles(value)
    original = BackInStock::RestockCheckJob::MAX_HANDLES_PER_CLIENT
    BackInStock::RestockCheckJob.send(:remove_const, :MAX_HANDLES_PER_CLIENT)
    BackInStock::RestockCheckJob.const_set(:MAX_HANDLES_PER_CLIENT, value)
    yield
  ensure
    BackInStock::RestockCheckJob.send(:remove_const, :MAX_HANDLES_PER_CLIENT)
    BackInStock::RestockCheckJob.const_set(:MAX_HANDLES_PER_CLIENT, original)
  end
end
