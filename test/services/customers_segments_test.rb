require 'test_helper'

class CustomersSegmentsTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def customer(email, city: nil)
    Customer.create!(email:, first_name: email.split('@').first.capitalize, shopify_customer_id: SecureRandom.hex(6),
                     default_address_city: city)
  end

  def order(customer, total:, at:, client: @client, coupon: nil, cancelled: false, product: nil)
    o = Order.create!(client:, customer:, shopify_order_id: SecureRandom.hex(6), shopify_creation_date: at,
                      total_price: total, subtotal_price: total, total_discounts: 0, discount_code: coupon,
                      cancelled_at: (Time.current if cancelled))
    o.order_items.create!(product:, sku: 'SKU-1', price: total, quantity: 1) if product
    o
  end

  def refresh = Customers::RefreshProfiles.new(@client).call

  def rules(*conditions) = { 'groups' => [{ 'conditions' => conditions }] }

  def matching(rules_hash)
    Segments::Rules.new(@client, Segments::Rules.sanitize(rules_hash)).scope.pluck(:email).sort
  end

  test 'refresh builds per-store profiles ignoring cancelled orders and other stores' do
    ana = customer('ana@example.com', city: 'Recife')
    order(ana, total: 100, at: 10.days.ago, coupon: 'VOLTA10')
    order(ana, total: 300, at: 2.days.ago)
    order(ana, total: 999, at: 1.day.ago, cancelled: true)
    order(ana, total: 50, at: 1.day.ago, client: Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(3)}@x.com"))

    assert_equal 1, refresh
    profile = @client.customer_profiles.sole
    assert_equal 2, profile.orders_count
    assert_equal 400, profile.total_spent
    assert_equal 200, profile.avg_ticket
    assert_equal 300, profile.last_order_total
    assert_equal 1, profile.coupons_used
    assert_equal 'Recife', profile.city
    assert profile.rfm_segment.present?
  end

  test 'refresh removes customers whose orders were all cancelled' do
    bia = customer('bia@example.com')
    o = order(bia, total: 100, at: 3.days.ago)
    refresh
    o.update!(cancelled_at: Time.current)

    assert_equal 0, refresh
  end

  test 'RFM: recent frequent big spenders are champions, old single buyers hibernate' do
    old = 5.times.map { |i| customer("old#{i}@example.com").tap { |c| order(c, total: 50, at: (400 + i).days.ago) } }
    vip = customer('vip@example.com')
    5.times { |i| order(vip, total: 1000, at: (i + 1).days.ago) }
    refresh

    assert_equal 'champion', @client.customer_profiles.find_by(customer: vip).rfm_segment
    assert_equal 'hibernating', @client.customer_profiles.find_by(customer: old.last).rfm_segment
  end

  test 'segment rules: AND inside a group, OR between groups' do
    a = customer('a@example.com', city: 'Recife')
    b = customer('b@example.com', city: 'Recife')
    c = customer('c@example.com', city: 'Natal')
    order(a, total: 100, at: 1.day.ago)
    2.times { order(b, total: 100, at: 1.day.ago) }
    order(c, total: 900, at: 200.days.ago)
    refresh

    and_rules = rules({ field: 'city', op: 'equals', value: 'recife' }, { field: 'orders_count', op: 'gte', value: '2' })
    assert_equal ['b@example.com'], matching(and_rules)

    or_rules = { 'groups' => [{ 'conditions' => [{ 'field' => 'orders_count', 'op' => 'eq', 'value' => '1' },
                                                 { 'field' => 'city', 'op' => 'equals', 'value' => 'Recife' }] },
                              { 'conditions' => [{ 'field' => 'total_spent', 'op' => 'gt', 'value' => '500' }] }] }
    assert_equal %w[a@example.com c@example.com], matching(or_rules)
    assert_equal ['c@example.com'], matching(rules({ field: 'last_order_at', op: 'more_than_days', value: '90' }))
  end

  test 'product, coupon, period and refusal-list criteria' do
    vestido = Product.create!(client: @client, shopify_product_name: 'Vestido Linho', sku: 'V1', tags: 'maderite, verão')
    a = customer('a@example.com')
    b = customer('b@example.com')
    order(a, total: 100, at: Date.new(2025, 11, 28).noon, coupon: 'BLACK20', product: vestido)
    order(b, total: 100, at: 1.day.ago)
    EmailSuppression.unsubscribe!(@client, 'b@example.com')
    refresh

    assert_equal ['a@example.com'], matching(rules({ field: 'product', op: 'contains', value: 'linho' }))
    assert_equal ['b@example.com'], matching(rules({ field: 'not_product', op: 'contains', value: 'linho' }))
    assert_equal ['a@example.com'], matching(rules({ field: 'product_tag', op: 'contains', value: 'maderite' }))
    assert_equal ['a@example.com'], matching(rules({ field: 'coupon_code', op: 'equals', value: 'black20' }))
    assert_equal ['a@example.com'],
                 matching(rules({ field: 'purchase_date', op: 'between', value: '2025-11-20', value2: '2025-12-02' }))
    assert_equal ['b@example.com'], matching(rules({ field: 'suppressed', op: 'yes' }))
    assert_equal ['a@example.com'], matching(rules({ field: 'suppressed', op: 'no' }))
  end

  test 'segment inside segment, static lists and unknown fields' do
    a = customer('a@example.com')
    b = customer('b@example.com')
    order(a, total: 100, at: 1.day.ago)
    order(b, total: 100, at: 1.day.ago)
    refresh

    list = @client.segments.create!(name: 'VIPs', kind: 'static')
    list.segment_memberships.create!(customer: a)
    assert_equal ['a@example.com'], list.profiles.pluck(:email)

    assert_equal ['b@example.com'], matching(rules({ field: 'segment', op: 'not_in', value: list.id.to_s }))
    sanitized = Segments::Rules.sanitize(rules({ field: 'drop table', op: 'eq', value: '1' }))
    assert_equal [], sanitized['groups']
  end

  test 'segments that reference each other do not loop' do
    order(customer('a@example.com'), total: 100, at: 1.day.ago)
    refresh
    one = @client.segments.create!(name: 'Um', rules: rules({ field: 'orders_count', op: 'gte', value: '1' }))
    two = @client.segments.create!(name: 'Dois', rules: rules({ field: 'segment', op: 'in', value: one.id.to_s }))
    one.update!(rules: rules({ field: 'segment', op: 'in', value: two.id.to_s }))

    assert_nothing_raised { two.profiles.count }
  end

  test 'every suggested template is valid and runs' do
    order(customer('a@example.com'), total: 100, at: 1.day.ago)
    refresh

    Segments::Templates.all.each do |key, template|
      segment = @client.segments.new(name: template[:name], rules: template[:rules])
      if key == 'tag_cliente'
        assert_not segment.valid?, 'o modelo de tag pede para escolher as tags'
        segment.rules = rules({ 'field' => 'customer_tag', 'op' => 'in', 'value' => ['vip'] })
      end
      assert segment.valid?, "#{key}: #{segment.errors.full_messages}"
      assert_nothing_raised { segment.profiles.count }
    end
  end

  # ---------------------------------------------- clientes sem compra e tags --

  def shopify_customer(email, tags: nil, client: @client)
    Customer.create!(email:, first_name: email.split('@').first.capitalize, shopify_customer_id: SecureRandom.hex(6),
                     tags:, client:)
  end

  def other_client = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(3)}@x.com")

  def tagged(operator, *values) = matching(rules({ 'field' => 'customer_tag', 'op' => operator, 'value' => values }))

  test 'refresh includes Shopify customers who never bought, without RFM, and ranks only buyers' do
    shopify_customer('lead@example.com', tags: 'lead-lp')
    shopify_customer('outra@example.com', client: other_client)
    5.times { |i| order(customer("b#{i}@example.com"), total: 100 * (i + 1), at: (i + 1).days.ago) }

    assert_equal 6, refresh
    lead = @client.customer_profiles.find_by!(email: 'lead@example.com')
    assert_equal 0, lead.orders_count
    assert_equal 0, lead.total_spent
    assert_equal 0, lead.avg_ticket
    assert_nil lead.last_order_at
    assert_nil lead.rfm_segment
    assert_equal [1, 2, 3, 4, 5], @client.customer_profiles.where('orders_count > 0').pluck(:m_score).sort
  end

  test 'a lead registration merged with a buyer keeps the purchase numbers' do
    lead = shopify_customer('ana@example.com', tags: 'lead-lp')
    buyer = customer('ANA@example.com')
    order(buyer, total: 120, at: 2.days.ago)

    refresh
    profile = @client.customer_profiles.sole
    assert_equal [lead.id, buyer.id].sort, profile.merged_customer_ids.sort
    assert_equal 1, profile.orders_count
    assert_equal 120, profile.last_order_total
    assert profile.rfm_segment.present?
  end

  test 'customer tag: any, all or none of the tags, ignoring case and spacing, across merged registrations' do
    shopify_customer('ana@example.com', tags: 'lead-lp, VIP')
    shopify_customer('bia@example.com', tags: 'Lead-LP')
    shopify_customer('cris@example.com', tags: 'atacado')
    shopify_customer('duda@example.com')
    order(customer('cris@example.com').tap { |c| c.update!(tags: 'vip') }, total: 50, at: 1.day.ago)
    refresh

    assert_equal %w[ana@example.com bia@example.com], tagged('in', ' lead-lp ')
    assert_equal %w[ana@example.com bia@example.com cris@example.com], tagged('in', 'lead-lp', 'vip')
    assert_equal %w[ana@example.com cris@example.com], tagged('all', 'VIP', 'vip')
    assert_equal %w[ana@example.com], tagged('all', 'lead-lp', 'vip')
    assert_equal %w[duda@example.com], tagged('not_in', 'lead-lp', 'vip')
    assert_equal [], tagged('in', 'lead')
    assert_equal [], tagged('in')
  end

  test 'customer tag options list the tags of this store only, most used first' do
    shopify_customer('ana@example.com', tags: 'lead-lp, VIP')
    shopify_customer('bia@example.com', tags: 'Lead-LP ')
    shopify_customer('outra@example.com', tags: 'secreta', client: other_client)
    refresh

    assert_equal %w[Lead-LP VIP], Segments::CustomerTagOptions.new(@client).call.pluck(:key)
  end

  test 'a segment with the customer tag condition needs at least one tag' do
    empty = rules({ 'field' => 'customer_tag', 'op' => 'in', 'value' => [] })
    segment = @client.segments.new(name: 'Leads', rules: empty)

    assert_not segment.valid?
    assert_includes segment.errors.full_messages.join, 'Escolha pelo menos uma tag'
  end

  def person(first_name, email: nil, phone: nil, marketing: nil)
    Customer.create!(first_name:, email:, phone:, email_marketing_state: marketing, shopify_customer_id: SecureRandom.hex(6))
  end

  test 'registrations with the same e-mail become one profile on the oldest customer' do
    old = person('Bruna', email: 'Bruna@Example.com')
    recent = person('Bruna', email: 'bruna@example.com')
    order(old, total: 100, at: 30.days.ago)
    order(recent, total: 200, at: 2.days.ago)

    assert_equal 1, refresh
    profile = @client.customer_profiles.sole
    assert_equal old.id, profile.customer_id
    assert_equal [old.id, recent.id].sort, profile.merged_customer_ids.sort
    assert_equal 2, profile.orders_count
    assert_equal 300, profile.total_spent
  end

  test 'without e-mail it merges by phone only when the first name also matches' do
    a = person('Carla', phone: '+55 11 97085-4645')
    b = person('Carla', phone: '(11) 970854645')
    c = person('Marina', phone: '11970854645')
    [a, b, c].each { |customer| order(customer, total: 100, at: 5.days.ago) }

    assert_equal 2, refresh
    assert_equal [1, 2], @client.customer_profiles.pluck(:orders_count).sort
  end

  test 'keeps the most restrictive marketing state among merged registrations' do
    person_a = person('Dani', email: 'dani@example.com', marketing: 'subscribed')
    person_b = person('Dani', email: 'dani@example.com', marketing: 'unsubscribed')
    order(person_a, total: 10, at: 3.days.ago)
    order(person_b, total: 10, at: 2.days.ago)
    refresh

    assert_equal 'unsubscribed', @client.customer_profiles.sole.email_marketing_state
  end

  test 'marketing rule filters by state and treats missing as unknown' do
    subscribed = person('Eva', email: 'eva@example.com', marketing: 'subscribed')
    other = person('Gil', email: 'gil@example.com', marketing: 'not_subscribed')
    unknown = person('Hugo', email: 'hugo@example.com')
    [subscribed, other, unknown].each { |customer| order(customer, total: 10, at: 3.days.ago) }
    refresh

    in_rule = rules('field' => 'email_marketing', 'op' => 'in', 'value' => %w[subscribed])
    assert_equal ['eva@example.com'], matching(in_rule)
    unknown_rule = rules('field' => 'email_marketing', 'op' => 'in', 'value' => %w[unknown])
    assert_equal ['hugo@example.com'], matching(unknown_rule)
    not_rule = rules('field' => 'email_marketing', 'op' => 'not_in', 'value' => %w[subscribed])
    assert_equal %w[gil@example.com hugo@example.com], matching(not_rule)
  end

  test 'duplicating copies the rules of a segment and the members of a list' do
    dynamic = @client.segments.create!(name: 'Fieis', kind: 'dynamic', rules: rules('field' => 'orders_count', 'op' => 'gte', 'value' => '3'))
    ana = person('Ana', email: 'ana@example.com')
    list = @client.segments.create!(name: 'VIPs', kind: 'static')
    SegmentMembership.create!(segment: list, customer: ana)

    copy = dynamic.duplicate!
    list_copy = list.duplicate!

    assert_equal 'Cópia de Fieis', copy.name
    assert_equal dynamic.rules, copy.rules
    assert_equal [ana.id], list_copy.segment_memberships.pluck(:customer_id)
    assert_not_equal list.id, list_copy.id
  end
end
