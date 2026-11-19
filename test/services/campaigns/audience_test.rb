require 'test_helper'

class AudienceTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def profile(email, state: nil, phone: nil, name: 'Cli')
    customer = Customer.create!(first_name: 'Cli', email:, shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, email:, phone:, name:, email_marketing_state: state,
                            refreshed_at: Time.current)
  end

  def list(*profiles)
    segment = @client.segments.create!(name: "Lista #{SecureRandom.hex(2)}", kind: 'static')
    profiles.each { |p| SegmentMembership.create!(segment:, customer_id: p.customer_id) }
    segment
  end

  def everyone
    @client.segments.create!(name: 'Todos', kind: 'dynamic', rules: { 'groups' => [{ 'conditions' => [
                               { 'field' => 'orders_count', 'op' => 'gte', 'value' => '0' }
                             ] }] })
  end

  test 'counts recipients, leaves out suppressed and missing e-mails, and reports consent without blocking' do
    profile('a@example.com', state: 'subscribed')
    profile('b@example.com', state: 'not_subscribed')
    profile('c@example.com')
    profile('d@example.com', state: 'subscribed')
    profile(nil)
    @client.email_suppressions.create!(email: 'd@example.com', source: 'manual')

    result = Campaigns::Audience.new(@client, everyone).call

    assert_equal 5, result.total
    assert_equal 1, result.without_email
    assert_equal 1, result.suppressed
    assert_equal 3, result.recipients
    assert_equal 1, result.subscribed
    assert_equal 2, result.not_subscribed
  end

  test 'cost is price per thousand and the daily limit comes from the client plan' do
    @client.update!(daily_email_limit: 5000)
    2.times { |i| profile("p#{i}@example.com") }

    result = Campaigns::Audience.new(@client, everyone).call

    assert_equal BigDecimal('0.008'), result.cost
    assert_equal 5000, result.daily_limit
    assert_equal 0, result.used_today
  end

  test 'without a segment nobody receives' do
    result = Campaigns::Audience.new(@client, nil).call

    assert_equal 0, result.recipients
    assert_equal 0, result.cost
  end

  test 'a person in two chosen segments counts once' do
    ana = profile('ana@example.com')
    bia = profile('bia@example.com')
    result = Campaigns::Audience.new(@client, [list(ana, bia), list(ana)]).call
    assert_equal 2, result.total
    assert_equal 2, result.recipients
  end

  test 'whatsapp: the same number in three formats is sent once and people without a phone are left out' do
    ana = profile('ana@example.com', phone: '(16) 99237-5432', name: 'Ana Souza')
    dup1 = profile('x@example.com', phone: '16992375432')
    dup2 = profile('y@example.com', phone: '+5516992375432')
    bia = profile('bia@example.com', phone: '31 99013-1953', name: 'Bia')
    none = profile('c@example.com', phone: nil)
    bad = profile('d@example.com', phone: '123')
    audience = Campaigns::Audience.new(@client, [list(ana, dup1, dup2, bia, none, bad)], channel: 'whatsapp')

    result = audience.call
    assert_equal 6, result.total
    assert_equal 2, result.without_phone
    assert_equal 2, result.recipients

    sent = []
    audience.each_recipient { |profile, phone| sent << [profile.name, phone] }
    assert_equal [['Ana Souza', '+5516992375432'], ['Bia', '+5531990131953']], sent.sort
  end

  test 'e-mail each_recipient yields the address and skips suppressed ones' do
    profile('a@example.com')
    profile('d@example.com')
    @client.email_suppressions.create!(email: 'd@example.com', source: 'manual')
    sent = []
    Campaigns::Audience.new(@client, everyone).each_recipient { |_profile, email| sent << email }
    assert_equal ['a@example.com'], sent
  end
end
