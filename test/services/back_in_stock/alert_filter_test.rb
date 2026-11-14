require 'test_helper'

class BackInStock::AlertFilterTest < ActiveSupport::TestCase
  NOW = Time.zone.local(2026, 11, 14, 12, 0)

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def alert(email, variant: 1, variant_title: 'P/36 / PRETA', product: 10, status: 'pending', created: NOW - 5.days, **attrs)
    BackInStockAlert.create!(client: @client, shopify_product_id: product, shopify_variant_id: variant, product_handle: 'p',
                             product_title: 'Vestido', variant_title:, email:, status:, created_at: created, **attrs)
  end

  def filtered(params = {}, status = 'pending')
    filter = BackInStock::AlertFilter.new(@client, params, status:)
    filter.apply(@client.back_in_stock_alerts.where(status:)).pluck(:email).sort
  end

  def product(product_id, tags)
    Product.create!(client: @client, shopify_product_name: 'Vestido', shopify_product_id: product_id.to_s,
                    shopify_variant_id: product_id.to_s, tags:, sku: SecureRandom.hex(3))
  end

  test 'without filters nothing is removed' do
    alert('a@example.com')

    assert_equal %w[a@example.com], filtered
  end

  test 'period keeps only the requests inside the dates' do
    alert('in@example.com', created: Time.zone.local(2026, 11, 10, 10, 0))
    alert('out@example.com', created: Time.zone.local(2026, 10, 1, 10, 0))

    assert_equal %w[in@example.com], filtered(de: '2026-11-01', ate: '2026-11-14')
    assert_equal %w[in@example.com], filtered(de: '2026-11-01')
    assert_equal %w[out@example.com], filtered(ate: '2026-10-31')
  end

  test 'size matches the size part of the variant title, in any position' do
    alert('p@example.com', variant_title: 'P/36 / PRETA', variant: 1)
    alert('p2@example.com', variant_title: 'PRETO / P/36', variant: 2)
    alert('g@example.com', variant_title: 'G/42 / PRETA', variant: 3)
    alert('gg@example.com', variant_title: 'GG/44 / PRETA', variant: 4)

    assert_equal %w[p2@example.com p@example.com], filtered(tamanho: ['P'])
    assert_equal %w[g@example.com p2@example.com p@example.com], filtered(tamanho: %w[p G])
    assert_equal %w[gg@example.com], filtered(tamanho: ['GG'])
  end

  test 'category matches the tags of the product, ignoring case and spacing' do
    product(10, 'Roupas, Blusas')
    product(20, 'Roupas, Vestidos')
    alert('blusa@example.com', product: 10)
    alert('vestido@example.com', product: 20, variant: 2)

    assert_equal %w[blusa@example.com], filtered(categoria: ['blusas'])
    assert_equal %w[blusa@example.com vestido@example.com], filtered(categoria: %w[Blusas Vestidos])
    assert_equal [], filtered(categoria: ['Calças'])
  end

  test 'waiting age filters by how long ago the request was made' do
    alert('new@example.com', created: Time.current - 1.day)
    alert('mid@example.com', created: Time.current - 20.days)
    alert('old@example.com', created: Time.current - 200.days)

    assert_equal %w[new@example.com], filtered(espera: 'lt3')
    assert_equal %w[mid@example.com], filtered(espera: '10_30')
    assert_equal %w[old@example.com], filtered(espera: 'gt90')
  end

  test 'minimum demand is exposed for the grouping and sanitized' do
    assert_equal 3, BackInStock::AlertFilter.new(@client, { demanda: '3' }, status: 'pending').min_demand
    assert_nil BackInStock::AlertFilter.new(@client, { demanda: '0' }, status: 'pending').min_demand
    assert_nil BackInStock::AlertFilter.new(@client, { demanda: 'abc' }, status: 'pending').min_demand
    assert_equal 9999, BackInStock::AlertFilter.new(@client, { demanda: '999999' }, status: 'pending').min_demand
  end

  test 'notice status uses the strongest tracked event of each notice' do
    events = { 'click' => %w[delivery open click], 'open' => %w[delivery open], 'delivery' => %w[delivery], 'bounce' => %w[bounce] }
    events.each_key do |name|
      sent = alert("#{name}@example.com", status: 'notified', notified_at: NOW - 1.day)
      events[name].each do |type|
        EmailEvent.create!(client: @client, source: 'back_in_stock', back_in_stock_alert: sent, event_type: type,
                           ses_message_id: "m-#{name}", occurred_at: NOW)
      end
    end
    alert('plain@example.com', status: 'notified', notified_at: NOW - 2.days)

    assert_equal %w[click@example.com], filtered({ aviso: 'clique' }, 'notified')
    assert_equal %w[open@example.com], filtered({ aviso: 'abriu' }, 'notified')
    assert_equal %w[delivery@example.com], filtered({ aviso: 'entregue' }, 'notified')
    assert_equal %w[bounce@example.com], filtered({ aviso: 'devolvido' }, 'notified')
    assert_equal %w[plain@example.com], filtered({ aviso: 'sem_rastreio' }, 'notified')
  end

  test 'bought after the notice splits notified alerts' do
    variant = Product.create!(client: @client, shopify_product_name: 'Vestido', shopify_variant_id: '555', sku: 'V1', price: 300)
    alert('buyer@example.com', variant: 555, status: 'notified', notified_at: NOW - 3.days)
    alert('silent@example.com', variant: 555, status: 'notified', notified_at: NOW - 3.days)
    customer = Customer.create!(shopify_customer_id: 'c1', first_name: 'B', email: 'buyer@example.com')
    CustomerProfile.create!(client: @client, customer:, name: 'B', email: 'buyer@example.com', refreshed_at: Time.current)
    order = Order.create!(client: @client, customer:, shopify_order_id: 'o1', total_price: 400, shopify_creation_date: NOW - 2.days)
    OrderItem.create!(order:, product: variant, sku: 'V1', quantity: 1, price: 300)

    assert_equal %w[buyer@example.com], filtered({ comprou: 'sim' }, 'notified')
    assert_equal %w[silent@example.com], filtered({ comprou: 'nao' }, 'notified')
  end

  test 'notice and bought filters are ignored outside the notified tab' do
    alert('a@example.com')

    assert_equal %w[a@example.com], filtered(aviso: 'clique', comprou: 'sim')
  end

  test 'invalid values are ignored' do
    alert('a@example.com')

    params = { de: 'ontem', espera: 'nunca', tamanho: [''], categoria: [' '], aviso: 'x' }
    filter = BackInStock::AlertFilter.new(@client, params, status: 'notified')

    assert_equal({}, filter.to_params)
    assert_equal 0, filter.active_count
  end

  test 'chips describe each active filter and know how to remove it' do
    filter = BackInStock::AlertFilter.new(@client, { de: '2026-11-01', ate: '2026-11-14', tamanho: %w[P G], demanda: '3', espera: 'lt3' },
                                          status: 'pending')

    labels = filter.chips.map { |chip| chip[:label] }

    expected = ['Período: de 01/11/2026 até 14/11/2026', 'Tamanho: P, G', 'Solicitado há: menos de 3 dias', 'Pelo menos 3 pessoas']
    assert_equal expected, labels
    assert_equal 4, filter.active_count
    period_chip = filter.chips.first
    assert_not period_chip[:params].key?(:de)
    assert_not period_chip[:params].key?(:ate)
    assert_equal %w[P G], period_chip[:params][:tamanho]
  end
end
