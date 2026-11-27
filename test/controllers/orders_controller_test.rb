require 'test_helper'

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    @client = Client.create!(name: 'Loja', email: "c-#{SecureRandom.hex(4)}@example.com")
    sign_in User.create!(name: 'User', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
    Order.create!(client: @client, shopify_order_id: '1', shopify_order_number: '#1001', total_price: 350,
                  discount_code: 'BLACK', total_discounts: 35, shopify_creation_date: 1.day.ago)
  end

  test 'opens on the dashboard tab' do
    get orders_path

    assert_response :success
    assert_includes response.body, 'Faturamento e pedidos por dia'
    assert_includes response.body, 'Cupons mais usados'
    assert_includes response.body, 'BLACK'
    assert_includes response.body, 'po-chart-data'
  end

  test 'orders tab keeps the order list with filters and export' do
    get orders_path(aba: 'pedidos')

    assert_response :success
    assert_includes response.body, 'Exportar XLSX'
    assert_includes response.body, '#1001'
  end
end
