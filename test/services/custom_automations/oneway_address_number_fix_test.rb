require 'test_helper'

class CustomAutomations::OnewayAddressNumberFixTest < ActiveSupport::TestCase
  Fix = CustomAutomations::OnewayAddressNumberFix

  class FakeGateway
    attr_reader :updates, :since

    def initialize(orders, errors: [])
      @orders = orders
      @errors = errors
      @updates = []
    end

    def unfulfilled_orders_since(since)
      @since = since
      @orders
    end

    def update_shipping_address(order_id, address)
      @updates << [order_id, address]
      @errors
    end
  end

  def fix(address1, address2 = '', city = 'São Paulo')
    Fix.fix('address1' => address1, 'address2' => address2, 'city' => city)
  end

  test 'moves a bare number from the complement to the street' do
    assert_equal({ 'address1' => 'Rua Pio IV, 210', 'address2' => '' }, fix('Rua Pio IV', '210'))
    assert_equal({ 'address1' => 'Rua Santa Clara, 289', 'address2' => '302' }, fix('Rua Santa Clara', '289 /302'))
  end

  test 'keeps the rest of the complement after the number' do
    assert_equal({ 'address1' => 'Rua X, 10', 'address2' => 'apto 3' }, fix('Rua X', '10 apto 3'))
    assert_equal({ 'address1' => 'Rua X, 45B', 'address2' => 'casa 2' }, fix('Rua X ', '45B - casa 2'))
    assert_equal({ 'address1' => 'Rua X, 12', 'address2' => '' }, fix('Rua X', 'nº 12'))
    assert_equal({ 'address1' => 'Estrada Velha, S/N', 'address2' => 'sítio' }, fix('Estrada Velha', 's/n sítio'))
  end

  test 'fixes accented capitals in the middle of words, including the city' do
    assert_equal({ 'address1' => 'Rua Dr Granadeiro Guimarães, 1691', 'address2' => 'rua da Figueira 26',
                   'city' => 'Taubaté' },
                 fix('Rua Dr Granadeiro GuimarÃes', '1691, rua da Figueira 26', 'TaubatÉ'))
    assert_equal({ 'address1' => 'Rua Motorista Flávio Saraiva, 44' }, fix('Rua Motorista FlÁvio Saraiva, 44', 'Apto 101'))
    assert_equal({ 'city' => 'São Paulo' }, fix('Rua Lópes Quintas, 977', '', 'SÃo Paulo'))
    assert_nil fix('RUA SÃO JOÃO, 10', '', 'SÃO PAULO')
  end

  test 'removes repeated numbers and a complement that only repeats the number' do
    assert_equal({ 'address1' => 'Rua João Da Costa, 76', 'address2' => '' }, fix('Rua JoÃo Da Costa, 76 76', '76'))
    assert_equal({ 'address1' => 'Rua Coronel Domingos Ferreira, 510', 'address2' => '' },
                 fix('Rua Coronel Domingos Ferreira, 510, 510, 510 - 510 - 510', '510'))
    assert_equal({ 'address1' => 'Rua Maria José Belo Alvarenga, 50', 'address2' => '' },
                 fix('Rua Maria JosÉ Belo Alvarenga, 50', '50'))
    assert_equal({ 'address1' => 'Avenida Macuco, 212', 'address2' => '' }, fix('Avenida Macuco, 212 212', '212'))
  end

  test 'removes the complement glued to the end of the street' do
    assert_equal({ 'address1' => 'Rua Nossa Senhora De Nazaré, 385' },
                 fix('Rua Nossa Senhora De NazarÉ, 385 Casa 22', 'Casa 22'))
  end

  test 'leaves addresses that are already right or ambiguous' do
    assert_nil fix('Rua Karl Richter 69', 'apto 41')
    assert_nil fix('Rua Pio IV, 210', '')
    assert_nil fix('Rua Elza Brandão Rodarte 81', '17')
    assert_nil fix('Rua X 210', '10')
    assert_nil fix('Avenida Lúcio Costa 4350', 'Bloco 2 apt 202')
    assert_nil fix('Rua Torio, Coroado', 'Casa Tom&jerry')
    assert_nil fix('Rua X', '2º andar')
    assert_nil fix('Rua X', '3 andar')
    assert_nil fix('', '210')
  end

  test 'updates only orders that need it, sending the full address' do
    address = { 'firstName' => 'Helena', 'lastName' => 'Gurgel', 'address1' => 'Rua Pio IV', 'address2' => '210',
                'city' => 'São Paulo', 'provinceCode' => 'SP', 'zip' => '05657-110', 'countryCodeV2' => 'BR',
                'phone' => '+5511999999999' }
    ok = address.merge('address1' => 'Rua Karl Richter 69', 'address2' => 'apto 41')
    gateway = FakeGateway.new([
                                { 'id' => 'gid://shopify/Order/1', 'name' => '#38517', 'shippingAddress' => address },
                                { 'id' => 'gid://shopify/Order/2', 'name' => '#38515', 'shippingAddress' => ok },
                                { 'id' => 'gid://shopify/Order/3', 'name' => '#38500', 'shippingAddress' => nil }
                              ])
    results = Fix.new(Client.new(name: 'OneWay'), lookback_hours: 72, gateway: gateway).call

    assert_in_delta 72.hours.ago, gateway.since, 5
    assert_equal 1, gateway.updates.size
    order_id, sent = gateway.updates.first
    assert_equal 'gid://shopify/Order/1', order_id
    assert_equal 'Rua Pio IV, 210', sent['address1']
    assert_equal '', sent['address2']
    assert_equal 'Gurgel', sent['lastName']
    assert_equal ['#38517'], results.map(&:order_name)
    assert_nil results.first.error
  end

  test 'reports Shopify errors on the result' do
    gateway = FakeGateway.new([{ 'id' => 'gid://shopify/Order/1', 'name' => '#1',
                                 'shippingAddress' => { 'address1' => 'Rua X', 'address2' => '5' } }],
                              errors: ['Address is invalid'])

    results = Fix.new(Client.new(name: 'OneWay'), gateway: gateway).call

    assert_equal 'Address is invalid', results.first.error
  end
end
