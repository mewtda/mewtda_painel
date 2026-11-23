require 'test_helper'

class Billing::MonthlyChargeTest < ActiveSupport::TestCase
  class FakeAsaas
    attr_reader :payments_created, :customers_created, :customers_updated

    def initialize(existing_payment: nil, existing_customer: nil, fail_with: nil)
      @existing_payment = existing_payment
      @existing_customer = existing_customer
      @fail_with = fail_with
      @payments_created = []
      @customers_created = []
      @customers_updated = []
    end

    def update_customer(id, **args)
      @customers_updated << [id, args]
      { 'id' => id }
    end

    def find_customer(_doc) = @existing_customer

    def create_customer(**args)
      @customers_created << args
      { 'id' => 'cus_1' }
    end

    def find_payment(_ref) = @existing_payment

    def create_payment(**args)
      raise Billing::AsaasApi::Error, @fail_with if @fail_with

      @payments_created << args
      { 'id' => 'pay_1', 'invoiceUrl' => 'https://asaas.test/i/pay_1', 'dueDate' => args[:due_date].iso8601 }
    end
  end

  def setup
    @client = Client.create!(name: 'OneWay', email: "ow-#{SecureRandom.hex(4)}@example.com",
                             plan_name: 'Pro', plan_price: '297,00', billing_document: '12.345.678/0001-90',
                             billing_email: 'financeiro@oneway.test', billing_phone: '(31) 99876-5432')
    @month = Date.new(2026, 10, 1)
  end

  test 'creates the customer and the payment for the closed month' do
    api = FakeAsaas.new

    charge = Billing::MonthlyCharge.new(@client, @month, api: api).call

    assert_equal 'created', charge.status
    assert_equal 'pay_1', charge.asaas_payment_id
    assert_equal 'https://asaas.test/i/pay_1', charge.invoice_url
    assert_equal BigDecimal('297'), charge.amount
    assert_equal [{ name: 'OneWay', cpf_cnpj: '12345678000190', email: 'financeiro@oneway.test',
                    mobile_phone: '31998765432' }], api.customers_created
    assert_equal 'cus_1', @client.reload.asaas_customer_id
    payment = api.payments_created.first
    assert_equal 'cus_1', payment[:customer]
    assert_equal "mewtda-client-#{@client.id}-2026-10", payment[:external_reference]
  end

  test 'does not charge twice for the same month' do
    api = FakeAsaas.new
    2.times { Billing::MonthlyCharge.new(@client, @month, api: api).call }

    assert_equal 1, api.payments_created.size
    assert_equal 1, BillingCharge.where(client: @client).count
  end

  test 'reuses a payment already in Asaas with the same reference' do
    api = FakeAsaas.new(existing_payment: { 'id' => 'pay_old', 'invoiceUrl' => 'u', 'dueDate' => '2026-11-06' },
                        existing_customer: { 'id' => 'cus_9' })

    charge = Billing::MonthlyCharge.new(@client, @month, api: api).call

    assert_equal 'pay_old', charge.asaas_payment_id
    assert_empty api.payments_created
  end

  test 'records the error and retries next time' do
    charge = Billing::MonthlyCharge.new(@client, @month, api: FakeAsaas.new(fail_with: 'CPF inválido')).call
    assert_equal 'failed', charge.status
    assert_equal 'CPF inválido', charge.error_message

    charge = Billing::MonthlyCharge.new(@client, @month, api: FakeAsaas.new).call
    assert_equal 'created', charge.status
  end

  test 'updates the billing contact of a customer already in Asaas before a new charge' do
    @client.update_columns(asaas_customer_id: 'cus_7', billing_email: nil)
    api = FakeAsaas.new

    Billing::MonthlyCharge.new(@client, @month, api: api).call

    assert_equal [['cus_7', { email: @client.email, mobile_phone: '31998765432' }]], api.customers_updated
    assert_empty api.customers_created
  end

  test 'a client with document needs a billing e-mail and phone' do
    client = Client.new(name: 'Nova', email: 'dona@nova.test', billing_document: '123')
    assert_not client.valid?
    assert client.errors.added?(:billing_email, :blank)
    assert client.errors.added?(:billing_phone, :blank)

    client.assign_attributes(billing_email: 'fin@nova.test', billing_phone: '+55 (31) 3333-4444')
    client.valid?
    assert_empty client.errors[:billing_email] + client.errors[:billing_phone]
    assert_equal '3133334444', client.billing_phone_digits
  end

  test 'skips clients without document or with an empty invoice' do
    @client.update!(billing_document: nil)
    assert_nil Billing::MonthlyCharge.new(@client, @month, api: FakeAsaas.new).call

    @client.update!(billing_document: '123', plan_price: 0)
    assert_nil Billing::MonthlyCharge.new(@client, @month, api: FakeAsaas.new).call
  end
end
