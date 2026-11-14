require 'test_helper'

class BackInStockControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    sign_in User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::USER, client: @client)
    @client.create_back_in_stock_setting!
  end

  def alert(email, title: 'Vestido', variant: 1, variant_title: 'P/36 / PRETA', **attrs)
    BackInStockAlert.create!({ client: @client, shopify_product_id: variant, shopify_variant_id: variant, product_handle: 'p',
                               product_title: title, variant_title:, email: }.merge(attrs))
  end

  test 'lists the waiting alerts and offers the filter panel' do
    alert('a@example.com')

    get back_in_stock_path

    assert_response :success
    assert_select 'summary', text: /Filtrar/
    assert_select '.bis-active-filters', count: 0
  end

  test 'applying filters refreshes the list live, with the loading state' do
    alert('a@example.com')

    get back_in_stock_path

    assert_select "form.bis-toolbar[data-live-regions='bis-filter-summary,bis-results']"
    assert_select '#bis-results[data-live-spinner]'
    assert_select '#bis-filter-summary'
  end

  test 'a size filter keeps only the matching products and shows the active chip' do
    alert('p@example.com', title: 'Blusa Pequena', variant: 1, variant_title: 'P/36 / PRETA')
    alert('g@example.com', title: 'Blusa Grande', variant: 2, variant_title: 'G/42 / PRETA')

    get back_in_stock_path(tamanho: ['P'])

    assert_match 'Blusa Pequena', response.body
    assert_no_match 'Blusa Grande', response.body
    assert_select '.bis-active-filters__chip', text: /Tamanho: P/
  end

  test 'minimum demand hides products with fewer people waiting' do
    2.times { |index| alert("many#{index}@example.com", title: 'Muito Pedido', variant: 1) }
    alert('few@example.com', title: 'Pouco Pedido', variant: 2)

    get back_in_stock_path(demanda: 2)

    assert_match 'Muito Pedido', response.body
    assert_no_match 'Pouco Pedido', response.body
  end

  test 'notice filters only appear in the notified tab' do
    alert('sent@example.com', status: 'notified', notified_at: 1.day.ago)

    get back_in_stock_path(status: 'pending')
    assert_select 'select[name=aviso]', count: 0

    get back_in_stock_path(status: 'notified')
    assert_select 'select[name=aviso]'
    assert_select 'select[name=comprou]'
  end

  test 'filters survive the status tabs links and can be cleared' do
    alert('a@example.com')

    get back_in_stock_path(tamanho: ['P'], q: 'vest')

    assert_select "a[href*='tamanho%5B%5D=P'][href*='status=notified']"
    assert_select '.bis-active-filters__clear'
  end

  test 'malformed filters never break the page' do
    alert('a@example.com')

    get back_in_stock_path(de: 'ontem', demanda: 'abc', espera: 'nunca', tamanho: [''], aviso: 'x')

    assert_response :success
    assert_select '.bis-active-filters', count: 0
  end
end
