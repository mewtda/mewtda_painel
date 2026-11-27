require 'test_helper'

class Shopify::CheckoutsTest < ActiveSupport::TestCase
  # Dublê do ShopifyAPI::Clients::Rest::Admin: devolve as páginas em ordem e guarda as consultas feitas.
  class FakeApi
    Response = Struct.new(:body, :next_page_info)

    attr_reader :queries

    def initialize(pages)
      @pages = pages
      @queries = []
    end

    def get(path:, query:)
      raise ArgumentError, "path inesperado: #{path}" unless path == 'checkouts'

      @queries << query
      @pages.fetch(@queries.size - 1)
    end
  end

  def checkout_payload(id, created_at)
    { 'id' => id, 'token' => "tok#{id}", 'email' => "c#{id}@example.com", 'phone' => '+5531999990000',
      'total_price' => '100.00', 'currency' => 'BRL', 'created_at' => created_at.iso8601,
      'updated_at' => created_at.iso8601, 'abandoned_checkout_url' => "https://loja.test/recover/#{id}",
      'completed_at' => nil, 'line_items' => [],
      'billing_address' => { 'first_name' => 'Maria', 'last_name' => 'Souza', 'phone' => '+5531999990000' } }
  end

  test 'guarda o nome de quem abandonou o checkout (endereço de cobrança, entrega ou cliente)' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    no_billing = checkout_payload(2, 1.hour.ago).merge('billing_address' => nil,
                                                       'shipping_address' => { 'first_name' => 'Ana', 'last_name' => '' })
    only_customer = checkout_payload(3, 1.hour.ago).merge('billing_address' => nil,
                                                          'customer' => { 'first_name' => 'Bia', 'last_name' => 'Lima' })
    api = FakeApi.new([FakeApi::Response.new({ 'checkouts' => [checkout_payload(1, 1.hour.ago), no_billing, only_customer] }, nil)])

    ShopifyAPI::Clients::Rest::Admin.stub(:new, api) do
      Shopify::Checkouts.sync_abandoned_checkouts_to_rails(session: nil, client: client)
    end

    names = client.abandoned_checkouts.order(:shopify_checkout_id).pluck(:customer_name)
    assert_equal ['Maria Souza', 'Ana', 'Bia Lima'], names
  end

  test 'segue a paginação só com page_info (a Shopify recusa status junto com page_info)' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    api = FakeApi.new([
                        FakeApi::Response.new({ 'checkouts' => [checkout_payload(1, 2.hours.ago)] }, 'pagina2'),
                        FakeApi::Response.new({ 'checkouts' => [checkout_payload(2, 1.hour.ago)] }, nil)
                      ])

    total = ShopifyAPI::Clients::Rest::Admin.stub(:new, api) do
      Shopify::Checkouts.sync_abandoned_checkouts_to_rails(session: nil, client: client)
    end

    assert_equal 2, total
    assert_equal %w[1 2], client.abandoned_checkouts.order(:shopify_checkout_id).pluck(:shopify_checkout_id)
    first, second = api.queries
    assert_equal 'open', first[:status]
    assert first[:created_at_min].present?
    assert_equal({ limit: 250, page_info: 'pagina2' }, second)
  end
end
