require 'test_helper'

class BackInStockPerformanceControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    sign_in User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
  end

  def activate = @client.create_back_in_stock_setting!

  def alert(**attrs)
    BackInStockAlert.create!({ client: @client, shopify_product_id: 1, shopify_variant_id: 555, product_handle: 'vestido',
                               product_title: 'Vestido Longo', variant_title: 'P', email: 'ana@example.com', price: 300,
                               created_at: 2.days.ago }.merge(attrs))
  end

  test 'redirects to the activation screen while the tool is not activated' do
    get back_in_stock_performance_path

    assert_redirected_to back_in_stock_path
  end

  test 'shows the quick reports, funnel and top products' do
    activate
    alert
    alert(email: 'bia@example.com', status: 'notified', notified_at: 1.day.ago)

    get back_in_stock_performance_path

    assert_response :success
    assert_match 'Desempenho do De volta ao estoque', response.body
    assert_match 'Produtos exigentes', response.body
    assert_match 'Receita recuperada', response.body
    assert_match 'Estado das solicitações', response.body
    assert_match 'Vestido Longo', response.body
    assert_match 'Enviado', response.body
  end

  test 'shows the tracked status of a notice' do
    activate
    sent = alert(status: 'notified', notified_at: 1.day.ago)
    EmailEvent.create!(client: @client, source: 'back_in_stock', back_in_stock_alert: sent, event_type: 'click',
                       ses_message_id: 'm-1', occurred_at: Time.current)

    get back_in_stock_performance_path

    assert_match 'Clicado', response.body
  end

  test 'a period without requests explains there is nothing yet' do
    activate

    get back_in_stock_performance_path(periodo: '7d')

    assert_match 'Nenhuma solicitação neste período', response.body
  end

  test 'exports the requests of the period as a spreadsheet' do
    activate
    alert
    alert(email: 'old@example.com', created_at: 200.days.ago)

    get export_back_in_stock_performance_path(periodo: '30d')

    assert_response :success
    sheet = RubyXL::Parser.parse_buffer(response.body)[0]
    assert_equal Spreadsheets::BackInStockAlerts::HEADERS, sheet[0].cells.map(&:value)
    assert_equal 'ana@example.com', sheet[1][3].value
    assert_nil sheet[2]
  end

  test 'never shows requests of another store' do
    activate
    other = Client.create!(name: 'Outra', email: "outra-#{SecureRandom.hex(4)}@example.com")
    BackInStockAlert.create!(client: other, shopify_product_id: 1, shopify_variant_id: 9, product_handle: 'x',
                             product_title: 'Produto Alheio', email: 'z@example.com', created_at: 1.day.ago)

    get back_in_stock_performance_path

    assert_no_match 'Produto Alheio', response.body
  end

  test 'the alerts screen links to the performance page' do
    activate

    get back_in_stock_path

    assert_includes response.body, back_in_stock_performance_path
  end
end
