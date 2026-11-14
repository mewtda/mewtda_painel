require 'test_helper'

class Segments::ProductRulesTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @blouse_g = product('Blusa Lisa', 'Roupas, Blusas', 'PRETO', 'G/42')
    @blouse_p = product('Blusa Lisa', 'Roupas, Blusas', 'PRETO', 'P/36')
    @dress_g = product('Vestido Midi', 'Roupas, Vestidos', 'G/42', 'AZUL')
  end

  def product(name, tags, option1, option2)
    Product.create!(client: @client, shopify_product_name: name, tags:, option1:, option2:, sku: SecureRandom.hex(3))
  end

  def buyer(name, *products)
    customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6), first_name: name, email: "#{name}@example.com")
    CustomerProfile.create!(client: @client, customer:, name:, email: customer.email, refreshed_at: Time.current)
    order = Order.create!(client: @client, customer:, shopify_order_id: SecureRandom.hex(5), total_price: 100,
                          shopify_creation_date: 1.day.ago)
    products.each { |item| OrderItem.create!(order:, product: item, sku: item.sku, quantity: 1, price: 50) }
    customer
  end

  def names(*conditions)
    rules = { 'groups' => [{ 'conditions' => conditions }] }
    Segments::Rules.new(@client, rules).scope.pluck(:name).sort
  end

  def cond(field, *values) = { 'field' => field, 'op' => 'in', 'value' => values }

  test 'category matches any tag of the purchased product, ignoring case and spacing' do
    buyer('ana', @blouse_g)
    buyer('bia', @dress_g)

    assert_equal %w[ana], names(cond('product_category', 'blusas'))
    assert_equal %w[ana bia], names(cond('product_category', 'Blusas', ' Vestidos '))
    assert_equal [], names(cond('product_category', 'Calças'))
  end

  test 'size matches the size token in any option, whatever its position' do
    buyer('ana', @blouse_g)
    buyer('bia', @blouse_p)
    buyer('cris', @dress_g)

    assert_equal %w[ana cris], names(cond('product_size', 'G'))
    assert_equal %w[bia], names(cond('product_size', 'p'))
    assert_equal %w[ana bia cris], names(cond('product_size', 'G', 'P'))
  end

  test 'size G does not match GG and colors are never read as sizes' do
    big = product('Blusa Maxi', 'Blusas', 'BRANCO', 'GG/44')
    buyer('ana', big)

    assert_equal [], names(cond('product_size', 'G'))
    assert_equal %w[ana], names(cond('product_size', 'GG'))
    assert_equal [], names(cond('product_size', 'PRETO'))
  end

  test 'category and size in the same group must come from the same item' do
    mixed = buyer('ana', @blouse_p, @dress_g)
    same = buyer('bia', @blouse_g)

    both = names(cond('product_category', 'Blusas'), cond('product_size', 'G'))

    assert_equal %w[bia], both
    assert_equal [mixed.first_name, same.first_name].sort, names(cond('product_category', 'Blusas'))
  end

  test 'category and size can be combined with other rules in the same group' do
    buyer('ana', @blouse_g)

    assert_equal %w[ana], names(cond('product_category', 'Blusas'), cond('product_size', 'G'),
                                { 'field' => 'orders_count', 'op' => 'gte', 'value' => '0' })
  end

  test 'ignores empty selections and cancelled orders' do
    customer = buyer('ana', @blouse_g)
    Order.where(customer:).update_all(cancelled_at: Time.current)

    assert_equal [], names(cond('product_category', 'Blusas'))
    assert_equal %w[ana], names(cond('product_category'), { 'field' => 'has_email', 'op' => 'yes' })
  end

  test 'sanitize keeps lists for the new fields' do
    conditions = [cond('product_size', 'G', 'P'), cond('product_category', 'Blusas')]
    clean = Segments::Rules.sanitize({ 'groups' => [{ 'conditions' => conditions }] })

    assert_equal([%w[G P], %w[Blusas]], clean['groups'].first['conditions'].map { |c| c['value'] })
  end

  test 'product options list the categories by popularity and only real sizes' do
    options = Segments::ProductOptions.new(@client)

    assert_equal(%w[Roupas Blusas Vestidos], options.categories.map { |c| c[:key] })
    assert_equal(%w[P G], options.sizes.map { |s| s[:key] })
  end
end
