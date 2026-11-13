require 'test_helper'

class Whatsapp::RouterTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja', email: "l-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    @automation = @client.automations.create!(name: 'Cashback', kind: :cashback, message: 'oi', days_after_purchase: 1,
                                          start_date: Date.current, end_date: Date.current + 30)
    @a = connect('A')
    @b = connect('B')
  end

  def connect(name, client: @client, state: 'connected')
    client.whatsapp_connections.create!(name: name, state: state)
  end

  def link(conn)
    Whatsapp::AutomationConnection.create!(automation: @automation, connection: conn)
  end

  test 'alterna entre os números conectados' do
    link(@a)
    link(@b)
    picks = 3.times.map { Whatsapp::Router.pick(automation: @automation, phone: '11999990000') }
    assert_equal [@a, @b, @a], picks
  end

  test 'ignora número desconectado' do
    link(@a)
    link(@b)
    @b.update!(state: 'disconnected')
    picks = 2.times.map { Whatsapp::Router.pick(automation: @automation, phone: '11999990000') }
    assert_equal [@a, @a], picks
  end

  test 'sem número conectado retorna nil' do
    link(@a)
    @a.update!(state: 'disconnected')
    assert_nil Whatsapp::Router.pick(automation: @automation, phone: '11999990000')
  end

  test 'prefer vence quando conectado e da campanha' do
    link(@a)
    link(@b)
    assert_equal @b, Whatsapp::Router.pick(automation: @automation, phone: '11999990000', prefer: @b)
  end

  test 'telefone que já tem contato num número fica nele' do
    link(@a)
    link(@b)
    Whatsapp::Contact.resolve!(@b, { 'remoteJid' => '5511999990000@s.whatsapp.net' })
    assert_equal @b, Whatsapp::Router.pick(automation: @automation, phone: '(11) 99999-0000')
    assert_equal @b, Whatsapp::Router.pick(automation: @automation, phone: '5511999990000')
  end

  test 'número de outro cliente não pode ser ligado' do
    other = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(4)}@example.com")
    link = Whatsapp::AutomationConnection.new(automation: @automation, connection: connect('X', client: other))
    assert_not link.valid?
    assert_includes link.errors[:connection], 'número de outro cliente'
  end

  test 'número de outro cliente ligado por fora da validação nunca é escolhido' do
    other = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(4)}@example.com")
    foreign = connect('X', client: other)
    Whatsapp::AutomationConnection.new(automation: @automation, connection: foreign).save!(validate: false)
    assert_nil Whatsapp::Router.pick(automation: @automation, phone: '11999990000')
    link(@a)
    3.times { assert_equal @a, Whatsapp::Router.pick(automation: @automation, phone: '11999990000', prefer: foreign) }
  end

  test 'primeira ligação marca evolution_started_at' do
    assert_nil @automation.evolution_started_at
    link(@a)
    assert_not_nil @automation.reload.evolution_started_at
  end

  test 'strict devolve só o preferido conectado, sem cair em outro número' do
    link(@a)
    link(@b)
    assert_equal @b, Whatsapp::Router.pick(automation: @automation, phone: '11999990000', prefer: @b, strict: true)
    @b.update!(state: 'disconnected')
    assert_nil Whatsapp::Router.pick(automation: @automation, phone: '11999990000', prefer: @b, strict: true)
    assert_nil Whatsapp::Router.pick(automation: @automation, phone: '11999990000', strict: true)
  end
end
