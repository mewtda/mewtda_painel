require 'test_helper'

class ProductsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    @client = Client.create!(name: 'Loja', email: "c-#{SecureRandom.hex(4)}@example.com")
    sign_in User.create!(name: 'User', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
    @product = Product.create!(client: @client, shopify_product_name: 'Vestido Poá', shopify_product_id: '10', sku: 'V1')
    order = Order.create!(client: @client, shopify_order_id: '1', shopify_creation_date: 1.day.ago)
    OrderItem.create!(order:, product: @product, sku: 'V1', price: 250, quantity: 2)
  end

  test 'opens on the dashboard tab with the ABC curve' do
    get products_path

    assert_response :success
    assert_includes response.body, 'Curva ABC (gráfico de Pareto)'
    assert_includes response.body, 'Vestido Poá'
    assert_includes response.body, 'R$ 500,00'
    assert_includes response.body, 'pa-chart-data'
  end

  test 'products tab lists the catalog with the curve of each product' do
    get products_path(aba: 'produtos')

    assert_response :success
    assert_includes response.body, 'Exportar XLSX'
    assert_includes response.body, 'pa-curve--a'
  end

  test 'dashboard with no sales explains why the curve is empty' do
    get products_path(p: '30', de: 3.years.ago.to_date.iso8601, ate: (3.years.ago.to_date + 1).iso8601)

    assert_response :success
    assert_includes response.body, 'Nenhum produto vendido no período'
  end
end
