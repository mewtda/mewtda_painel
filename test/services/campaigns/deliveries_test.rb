require 'test_helper'

class Campaigns::DeliveriesTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @ana = profile('Ana', email: 'ana@example.com', phone: '(31) 99999-0001')
    @bia = profile('Bia', email: 'bia@example.com', phone: '(31) 99999-0002')
    @caio = profile('Caio', email: 'caio@example.com', phone: nil)
    @segment = @client.segments.create!(name: 'Black', kind: 'static')
    [@ana, @bia, @caio].each { |p| SegmentMembership.create!(segment: @segment, customer_id: p.customer_id) }
    @campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sending', started_at: 1.hour.ago)
    @campaign.campaign_segments.create!(segment: @segment)
    @welcome = @campaign.messages.create!(channel: 'whatsapp', status: 'scheduled', position: 0,
                                          audience_frozen_at: 1.hour.ago, continuous_until: 1.day.from_now)
    @later = @campaign.messages.create!(channel: 'whatsapp', status: 'scheduled', position: 1, send_at: 1.day.from_now)
  end

  def profile(name, email:, phone:)
    customer = Customer.create!(first_name: name, email:, shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, email:, phone:, name:, refreshed_at: Time.current)
  end

  def recipient(profile, message, status, **attrs)
    @campaign.recipients.create!(message:, channel: 'whatsapp', customer_id: profile.customer_id, name: profile.name,
                                 phone: Whatsapp::Phone.normalize(profile.phone), status:, **attrs)
  end

  def cells(profile) = @deliveries.cells_for([profile]).fetch(profile.id)

  test 'shows per message who got it, who failed and why the others did not' do
    recipient(@ana, @welcome, 'sent', sent_at: 30.minutes.ago)
    @deliveries = Campaigns::Deliveries.new(@campaign)

    ana_welcome, ana_later = cells(@ana)
    assert_equal ['sent', 'Enviada'], [ana_welcome.status, ana_welcome.label]
    assert ana_welcome.at
    assert_equal 'missing', ana_later.status
    assert_equal 'A mensagem ainda não começou a sair', ana_later.detail

    assert_equal 'Sem celular válido no cadastro', cells(@caio).first.detail
    assert_equal 'Entrou no segmento depois; recebe na próxima rodada', cells(@bia).first.detail
  end

  test 'filters who received something and who received nothing' do
    recipient(@ana, @welcome, 'sent', sent_at: Time.current)
    recipient(@bia, @welcome, 'failed', error: 'Número sem WhatsApp')
    @deliveries = Campaigns::Deliveries.new(@campaign)

    assert_equal %w[Ana Bia Caio], @deliveries.profiles.order(:name).pluck(:name)
    assert_equal %w[Ana], @deliveries.profiles(filter: 'receberam').pluck(:name)
    assert_equal %w[Bia Caio], @deliveries.profiles(filter: 'nao_receberam').order(:name).pluck(:name)
    assert_equal %w[Bia], @deliveries.profiles(query: '0002').pluck(:name)
    assert_equal 'Número sem WhatsApp', cells(@bia).first.detail
  end

  test 'keeps people who got a message and later left the segment' do
    recipient(@ana, @welcome, 'sent', sent_at: Time.current)
    SegmentMembership.where(segment: @segment, customer_id: @ana.customer_id).delete_all

    assert_includes Campaigns::Deliveries.new(@campaign).profiles.pluck(:name), 'Ana'
  end

  test 'a second record with the same phone shows the delivery made to the first' do
    twin = profile('Ana 2', email: 'ana2@example.com', phone: '31 99999-0001')
    recipient(@ana, @welcome, 'sent', sent_at: Time.current)
    @deliveries = Campaigns::Deliveries.new(@campaign)

    cell = cells(twin).first
    assert_equal 'sent', cell.status
    assert_equal 'Mesmo número ou e-mail de outro cadastro', cell.detail
  end

  test 'filtered by channel shows only that channel messages and who received one of them' do
    email = @campaign.messages.create!(channel: 'email', status: 'sent', position: 2, audience_frozen_at: 1.hour.ago)
    recipient(@ana, @welcome, 'sent', sent_at: Time.current)
    @campaign.recipients.create!(message: email, channel: 'email', customer_id: @bia.customer_id, name: 'Bia',
                                 email: 'bia@example.com', status: 'sent', sent_at: Time.current)

    whatsapp = Campaigns::Deliveries.new(@campaign, channel: 'whatsapp')
    assert_equal [@welcome, @later], whatsapp.messages
    assert_equal %w[Ana], whatsapp.profiles(filter: 'receberam').pluck(:name)

    by_email = Campaigns::Deliveries.new(@campaign, channel: 'email')
    assert_equal [email], by_email.messages
    assert_equal %w[Bia], by_email.profiles(filter: 'receberam').pluck(:name)
    assert_equal %w[Ana Caio], by_email.profiles(filter: 'nao_receberam').order(:name).pluck(:name)

    assert_equal 3, Campaigns::Deliveries.new(@campaign, channel: 'outro').messages.size
  end
end
