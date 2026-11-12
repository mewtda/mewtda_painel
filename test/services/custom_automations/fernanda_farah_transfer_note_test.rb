require 'test_helper'

class CustomAutomations::FernandaFarahTransferNoteTest < ActiveSupport::TestCase
  class FakeTiny
    attr_reader :created_payload, :emitted_id

    def initialize(products: {}, emit_error: nil)
      @products = products
      @emit_error = emit_error
    end

    def account_info
      { 'razao_social' => 'FERNANDA FARAH DE AVILA LTDA', 'cnpj_cpf' => '20.203.489/0003-78',
        'inscricao_estadual' => '0023544790220', 'endereco' => 'RUA X', 'numero' => '428', 'complemento' => '',
        'bairro' => 'BELVEDERE', 'cep' => '30.320-670', 'cidade' => 'Belo Horizonte', 'estado' => 'MG',
        'fone' => '', 'email' => 'ecommerce@example.com' }
    end

    def find_product_by_code(code)
      @products[code]
    end

    def create_invoice(payload)
      @created_payload = payload
      { 'id' => '987', 'numero' => '000123', 'status' => 'OK' }
    end

    def emit_invoice(id)
      raise CustomAutomations::TinyApi::Error, @emit_error if @emit_error

      @emitted_id = id
      { 'status' => 'OK' }
    end
  end

  def setup
    @client = Client.create!(name: 'Fernanda Farah', email: "ff-#{SecureRandom.hex(4)}@example.com")
    @run = CustomAutomationRun.create!(client: @client, kind: 'fernanda_farah_transfer_note',
                                       period_start: Date.new(2026, 8, 1), period_end: Date.new(2026, 8, 31),
                                       order_filter: 'paid', price_percentage: 70)
    @matriz = FakeTiny.new(products: {
                             'SKU-A' => { 'nome' => 'Vestido A', 'ncm' => '6104.43.00', 'gtin' => '789',
                                          'unidade' => 'Un', 'origem' => '0', 'peso_bruto' => 0.3,
                                          'peso_liquido' => 0.3 }
                           })
  end

  def order(name:, lines:, financial_status: 'paid', cancelled_at: nil, refunds: [])
    { 'name' => name, 'financial_status' => financial_status, 'cancelled_at' => cancelled_at,
      'line_items' => lines, 'refunds' => refunds }
  end

  def line(id:, sku:, price:, quantity:, discount: 0)
    { 'id' => id, 'sku' => sku, 'title' => "Produto #{sku}", 'variant_title' => 'P', 'price' => price.to_s,
      'quantity' => quantity, 'discount_allocations' => [{ 'amount' => discount.to_s }] }
  end

  def build(orders)
    CustomAutomations::FernandaFarahTransferNote.new(@run, matriz: @matriz, ecommerce: FakeTiny.new,
                                                           shopify_orders: orders).build!
    @run.reload
  end

  test 'aggregates by SKU using 70% of the discounted average price and creates the pending note' do
    build([
            order(name: '#1', lines: [line(id: 1, sku: 'SKU-A', price: 100, quantity: 2, discount: 20)]),
            order(name: '#2', lines: [line(id: 2, sku: 'SKU-A', price: 100, quantity: 1)])
          ])

    item = @run.items.first
    assert_equal 'awaiting_review', @run.status
    assert_equal 3, item['quantity']
    assert_in_delta 93.33, item['average_price'], 0.001 # (180 + 100) / 3
    assert_in_delta 65.33, item['unit_value'], 0.001
    assert_in_delta 195.99, @run.total_value.to_f, 0.001
    assert_equal '6104.43.00', item['ncm']
    assert_equal '987', @run.tiny_note_id
    assert_equal '000123', @run.tiny_note_number

    nota = @matriz.created_payload['nota_fiscal']
    assert_equal CustomAutomations::FernandaFarahTransferNote::NATUREZA_OPERACAO, nota['natureza_operacao']
    assert_equal '20.203.489/0003-78', nota['cliente']['cpf_cnpj']
    assert_equal({ 'codigo' => 'SKU-A', 'quantidade' => '3', 'valor_unitario' => '65.33' },
                 nota['itens'].first['item'].slice('codigo', 'quantidade', 'valor_unitario'))
  end

  test 'paid filter skips cancelled and unpaid orders and subtracts refunded quantities' do
    build([
            order(name: '#1', lines: [line(id: 1, sku: 'SKU-A', price: 10, quantity: 3)],
                  refunds: [{ 'refund_line_items' => [{ 'line_item_id' => 1, 'quantity' => 1 }] }]),
            order(name: '#2', lines: [line(id: 2, sku: 'SKU-A', price: 10, quantity: 5)], cancelled_at: '2026-08-02'),
            order(name: '#3', lines: [line(id: 3, sku: 'SKU-A', price: 10, quantity: 7)], financial_status: 'pending')
          ])

    assert_equal 1, @run.orders_count
    assert_equal 2, @run.items.first['quantity']
  end

  test 'all filter keeps every order and ignores refunds' do
    @run.update!(order_filter: 'all')
    build([
            order(name: '#1', lines: [line(id: 1, sku: 'SKU-A', price: 10, quantity: 3)],
                  refunds: [{ 'refund_line_items' => [{ 'line_item_id' => 1, 'quantity' => 1 }] }]),
            order(name: '#2', lines: [line(id: 2, sku: 'SKU-A', price: 10, quantity: 5)], cancelled_at: '2026-08-02')
          ])

    assert_equal 8, @run.items.first['quantity']
  end

  test 'warns about SKUs missing from the matriz Tiny' do
    build([order(name: '#1', lines: [line(id: 1, sku: 'SKU-Z', price: 10, quantity: 1)])])

    assert_equal false, @run.items.first['tiny_found']
    assert(@run.warnings.any? { |w| w.include?('SKU-Z') && w.include?('não foi encontrado') })
  end

  test 'uses the current Shopify SKU of the variant instead of the one stored on the order' do
    old_line = line(id: 1, sku: 'SKU-VELHO', price: 10, quantity: 2).merge('variant_id' => 555)
    new_line = line(id: 2, sku: 'SKU-A', price: 10, quantity: 1).merge('variant_id' => 555)
    CustomAutomations::FernandaFarahTransferNote.new(@run, matriz: @matriz, ecommerce: FakeTiny.new,
                                                           shopify_orders: [order(name: '#1', lines: [old_line, new_line])],
                                                           current_skus: { 555 => 'SKU-A' }).build!
    @run.reload

    assert_equal 1, @run.items.size
    assert_equal 'SKU-A', @run.items.first['sku']
    assert_equal 3, @run.items.first['quantity']
    assert_equal true, @run.items.first['tiny_found']
    assert(@run.warnings.any? { |w| w.include?('SKU-VELHO') && w.include?('SKU-A') })
  end

  test 'fails without creating a note when there are no items' do
    build([])

    assert_equal 'failed', @run.status
    assert_nil @matriz.created_payload
  end

  test 'emit! transmits the note and marks it emitted' do
    @run.update!(status: 'emitting', tiny_note_id: '987')
    CustomAutomations::FernandaFarahTransferNote.new(@run, matriz: @matriz).emit!

    assert_equal 'emitted', @run.reload.status
    assert_equal '987', @matriz.emitted_id
  end

  test 'emit! returns to review with the error when Tiny rejects' do
    @run.update!(status: 'emitting', tiny_note_id: '987')
    tiny = FakeTiny.new(emit_error: 'Rejeição: NCM inválido')
    CustomAutomations::FernandaFarahTransferNote.new(@run, matriz: tiny).emit!

    assert_equal 'awaiting_review', @run.reload.status
    assert_includes @run.error_message, 'NCM inválido'
  end
end
