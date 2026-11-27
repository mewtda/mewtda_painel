require 'test_helper'

class CustomAutomations::WeeklySalesReportTest < ActiveSupport::TestCase
  # Segunda, 30/11/2026 às 9h (Brasília): a semana do relatório é 23 a 29/11.
  MONDAY = Time.find_zone('America/Sao_Paulo').local(2026, 11, 30, 9)

  class FakeShopify
    attr_reader :queries

    def initialize(nodes)
      @nodes = nodes
      @queries = []
    end

    def query(graphql)
      @queries << graphql
      { 'productVariants' => { 'pageInfo' => { 'hasNextPage' => false }, 'nodes' => @nodes } }
    end
  end

  class FakeSender
    attr_reader :sent

    def initialize = @sent = []

    def call(to:, subject:, html_body:)
      @sent << [to, subject, html_body]
      true
    end
  end

  setup do
    @client = Client.create!(name: 'FernandaFarah', email: "ff-#{SecureRandom.hex(4)}@example.com")
    vestido = Product.create!(client: @client, shopify_product_name: 'Vestido Lis', shopify_product_id: '1', sku: 'VL-P')
    order = Order.create!(client: @client, shopify_order_id: '1', total_price: 500,
                          shopify_creation_date: Time.zone.local(2026, 11, 26, 15))
    OrderItem.create!(order:, product: vestido, sku: 'VL-P', price: 250, quantity: 2)
    Order.create!(client: @client, shopify_order_id: '2', total_price: 999,
                  shopify_creation_date: Time.zone.local(2026, 11, 30, 8)) # fora da semana
    @setting = CustomAutomationSetting.for(@client, 'weekly_sales_report')
    @setting.recipients_text = "dona@ff.com.br, Financeiro@ff.com.br\ndona@ff.com.br"
    @setting.save!
  end

  def node(title, sku, quantity, tracked: true, status: 'ACTIVE')
    { 'title' => 'P', 'sku' => sku, 'inventoryQuantity' => quantity, 'inventoryItem' => { 'tracked' => tracked },
      'product' => { 'title' => title, 'status' => status } }
  end

  def report(now: MONDAY, force: false, nodes: [])
    CustomAutomations::WeeklySalesReport.new(@client, now:, force:, shopify: FakeShopify.new(nodes))
  end

  test 'sends last week summary and low stock to every recipient once per week' do
    sender = FakeSender.new
    nodes = [node('Blusa', 'BL-P', 3), node('Vestido Lis', 'VL-P', 1), node('Meia', 'M', 0, tracked: false),
             node('Rascunho', 'R', 1, status: 'DRAFT')]

    Ses::SendEmailService.stub(:new, ->(*_args, **_opts) { sender }) do
      assert_equal 2, report(nodes:).call
      assert_nil report(nodes:).call # já saiu nesta semana
    end

    assert_equal %w[dona@ff.com.br financeiro@ff.com.br], sender.sent.map(&:first)
    to, subject, html = sender.sent.first
    assert_equal 'dona@ff.com.br', to
    assert_equal 'Resumo da semana 23/11 a 29/11 · FernandaFarah', subject
    assert_includes html, 'R$ 500,00'
    assert_includes html, 'Vestido Lis'
    assert_includes html, 'Blusa'
    assert_not_includes html, 'Rascunho'
    assert_not_includes html, 'Meia'
    assert html.index('Vestido Lis', html.index('Estoque baixo')) < html.index('Blusa', html.index('Estoque baixo')),
           'a variante que vendeu na semana vem primeiro'
    assert_not_nil @setting.reload.last_run_at
  end

  test 'waits until Monday 8h and does nothing without recipients' do
    sender = FakeSender.new
    Ses::SendEmailService.stub(:new, ->(*_args, **_opts) { sender }) do
      assert_nil report(now: MONDAY.change(hour: 7)).call
      assert_nil report(now: MONDAY + 1.day).call # terça: não recupera a segunda perdida
      @setting.update!(settings: @setting.settings.merge('recipients' => []))
      assert_nil report(force: true).call
    end
    assert_empty sender.sent
  end

  test 'force sends again even after this week was sent or when disabled' do
    @setting.update!(last_run_at: MONDAY, settings: @setting.settings.merge('enabled' => false))
    sender = FakeSender.new

    Ses::SendEmailService.stub(:new, ->(*_args, **_opts) { sender }) do
      assert_nil report.call
      assert_equal 2, report(force: true).call
    end
  end

  test 'shows the Shopify error instead of failing when stock cannot be read' do
    shopify = Object.new
    shopify.define_singleton_method(:query) { |_q| raise StandardError, 'Access denied for inventoryQuantity' }
    html = CustomAutomations::WeeklySalesReport.new(@client, now: MONDAY, shopify:).to_html

    assert_includes html, 'Não foi possível ler o estoque na Shopify: Access denied'
  end
end
