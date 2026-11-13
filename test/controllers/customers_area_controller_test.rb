require 'test_helper'

class CustomersAreaControllerTest < ActionDispatch::IntegrationTest
  setup do
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    sign_in User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
    @ana = buyer('ana@example.com', 'Ana', orders: 3)
    @bia = buyer('bia@example.com', 'Bia', orders: 1)
    other = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(3)}@x.com")
    Order.create!(client: other, customer: Customer.create!(email: 'zeca@example.com', first_name: 'Zeca',
                                                            shopify_customer_id: SecureRandom.hex(5)),
                  shopify_order_id: SecureRandom.hex(6), shopify_creation_date: Time.current, total_price: 10)
  end

  def buyer(email, name, orders:)
    customer = Customer.create!(email:, first_name: name, shopify_customer_id: SecureRandom.hex(6))
    orders.times do |i|
      Order.create!(client: @client, customer:, shopify_order_id: SecureRandom.hex(6),
                    shopify_creation_date: (i + 1).days.ago, total_price: 100)
    end
    customer
  end

  test 'index computes profiles on first visit and only shows this store' do
    get customers_path

    assert_response :success
    assert_match 'Ana', response.body
    assert_match 'Bia', response.body
    assert_no_match 'Zeca', response.body
    assert_equal 2, @client.customer_profiles.count
  end

  test 'segments page computes profiles on first visit and recounts existing segments' do
    segment = @client.segments.create!(name: 'Recorrentes', kind: 'dynamic',
                                       rules: { 'groups' => [{ 'conditions' => [{ 'field' => 'orders_count', 'op' => 'gte', 'value' => '2' }] }] })
    assert_equal 0, @client.customer_profiles.count

    get segments_path

    assert_response :success
    assert_equal 2, @client.customer_profiles.count
    assert_equal 1, segment.reload.customers_count
  end

  test 'index filters by search, RFM and segment' do
    get customers_path(q: 'ana')
    assert_match 'Ana', response.body
    assert_no_match '>Bia<', response.body

    segment = @client.segments.create!(name: 'Recorrentes',
                                       rules: { 'groups' => [{ 'conditions' => [{ 'field' => 'orders_count', 'op' => 'gte', 'value' => '2' }] }] })
    get customers_path(segment_id: segment.id)
    assert_match 'Ana', response.body
    assert_no_match '>Bia<', response.body
  end

  test 'details returns the store profile and 404 for other stores customers' do
    get customers_path
    get details_customer_path(@ana), as: :json
    assert_response :success
    assert_equal 3, response.parsed_body.dig('customer', 'orders_count')

    get details_customer_path(Customer.find_by(email: 'zeca@example.com')), as: :json
    assert_response :not_found
  end

  test 'add_to_list creates a list with the selected customers' do
    get customers_path
    post add_to_list_customers_path, params: { customer_ids: [@ana.id, @bia.id], new_list_name: 'Black Friday' }

    list = @client.segments.find_by!(name: 'Black Friday')
    assert list.static?
    assert_equal 2, list.customers_count
  end

  test 'rfm page renders the matrix' do
    get rfm_customers_path(perfil: 'champion')

    assert_response :success
    assert_match 'Matriz RFM', response.body
    assert_match 'Campeão', response.body
  end

  test 'segments: create from builder, preview count, templates and destroy' do
    get customers_path
    rules = { groups: [{ conditions: [{ field: 'orders_count', op: 'gte', value: '2' }] }] }.to_json

    post preview_segments_path, params: { rules_json: rules }, as: :json
    assert_equal 1, response.parsed_body['count']
    assert_equal 2, response.parsed_body['total']

    post segments_path, params: { segment: { name: 'Recorrentes', kind: 'dynamic', rules_json: rules } }
    segment = @client.segments.find_by!(name: 'Recorrentes')
    assert_equal 1, segment.customers_count
    assert_redirected_to customers_path(segment_id: segment.id)

    get templates_segments_path
    assert_match 'Compraram apenas uma vez', response.body
    get new_segment_path(template: 'campeoes')
    assert_response :success
    get segments_path
    assert_match 'Recorrentes', response.body

    delete segment_path(segment)
    assert_not Segment.exists?(segment.id)
  end

  test 'a dynamic segment without conditions is rejected' do
    post segments_path, params: { segment: { name: 'Vazio', kind: 'dynamic', rules_json: '{"groups":[]}' } }

    assert_response :unprocessable_entity
    assert_match 'pelo menos uma condição', response.body
  end
end
