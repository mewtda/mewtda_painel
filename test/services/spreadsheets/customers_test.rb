require 'test_helper'

class Spreadsheets::CustomersTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def profile(name:, **attrs)
    customer = Customer.create!(shopify_customer_id: SecureRandom.hex(6), first_name: name, email: "#{name.downcase}@example.com")
    CustomerProfile.create!(client: @client, customer:, name:, email: customer.email, refreshed_at: Time.current, **attrs)
  end

  test 'writes the header and one ordered row per profile' do
    profile(name: 'Bia', city: 'Santos', orders_count: 2, total_spent: 300, avg_ticket: 150)
    profile(name: 'Ana', email_marketing_state: 'subscribed')

    sheet = Spreadsheets::Customers.new(@client.customer_profiles)
    workbook = RubyXL::Parser.parse_buffer(sheet.to_xlsx)[0]

    assert_equal Spreadsheets::Customers::HEADERS, workbook[0].cells.map(&:value)
    assert_equal %w[Ana Bia], [workbook[1][0].value, workbook[2][0].value]
    assert_equal 'Santos', workbook[2][3].value
    assert_equal 300.0, workbook[2][6].value
    assert_match(/\Aclientes_\d{8}_\d{4}\.xlsx\z/, sheet.filename)
  end
end
