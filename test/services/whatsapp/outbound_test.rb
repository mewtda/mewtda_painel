require 'test_helper'

class Whatsapp::OutboundTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @client = Client.create!(name: 'Loja', email: "l-#{SecureRandom.hex(4)}@example.com")
    @automation = @client.automations.create!(name: 'Cashback', kind: :cashback, message: 'oi', days_after_purchase: 1,
                                          start_date: Date.current, end_date: Date.current + 30)
  end

  def evolution!
    @conn = @client.whatsapp_connections.create!(name: 'A', state: 'connected')
    Whatsapp::AutomationConnection.create!(automation: @automation, connection: @conn)
  end

  test 'cria mensagem na fila do número da automação' do
    evolution!
    assert_difference 'Whatsapp::Message.count', 1 do
      assert_enqueued_with(job: Whatsapp::SendJob) do
        result = Whatsapp::Outbound.deliver(client: @client, automation: @automation, phone: '11999990000', body: 'oi')
        assert result.ok
        assert_equal 'evolution', result.provider
      end
    end
    msg = Whatsapp::Message.last
    assert_equal %w[queued automation outgoing text oi], [msg.state, msg.origin, msg.direction, msg.kind, msg.body]
    assert_equal '+5511999990000', msg.conversation.contact.phone
  end

  test 'duas entregas seguidas no mesmo número respeitam o intervalo' do
    evolution!
    r1 = Whatsapp::Outbound.deliver(client: @client, automation: @automation, phone: '11999990000', body: 'a')
    r2 = Whatsapp::Outbound.deliver(client: @client, automation: @automation, phone: '11988887777', body: 'b')
    assert_operator r2.message.send_after, :>=, r1.message.send_after + 8.seconds
  end

  test 'sem número conectado não cria nada' do
    evolution!
    @conn.update!(state: 'disconnected')
    assert_no_difference 'Whatsapp::Message.count' do
      result = Whatsapp::Outbound.deliver(client: @client, automation: @automation, phone: '11999990000', body: 'oi')
      assert_not result.ok
      assert_equal 'sem número responsável conectado', result.error
    end
  end

  test 'sem automação não envia' do
    evolution!
    result = Whatsapp::Outbound.deliver(client: @client, automation: nil, phone: '11999990000', body: 'oi')
    assert_not result.ok
  end

  test 'o job é enfileirado fora da transação, com a mensagem já persistida' do
    evolution!
    baseline = Whatsapp::Message.connection.open_transactions
    seen = nil
    original = Whatsapp::SendJob.method(:set)
    Whatsapp::SendJob.define_singleton_method(:set) do |*args, **kw|
      seen = Whatsapp::Message.connection.open_transactions
      original.call(*args, **kw)
    end
    begin
      result = Whatsapp::Outbound.deliver(client: @client, automation: @automation, phone: '11999990000', body: 'oi')
    ensure
      Whatsapp::SendJob.define_singleton_method(:set, original)
    end
    assert_equal baseline, seen
    assert_enqueued_with(job: Whatsapp::SendJob, args: [result.message.id])
    assert Whatsapp::Message.exists?(result.message.id)
  end

  test 'dentro de transação externa o job só é enfileirado após o commit' do
    evolution!
    result = nil
    ActiveRecord::Base.transaction do
      result = Whatsapp::Outbound.deliver(client: @client, automation: @automation, phone: '11999990000', body: 'oi')
      assert result.ok
      assert_no_enqueued_jobs(only: Whatsapp::SendJob)
    end
    assert_enqueued_with(job: Whatsapp::SendJob, args: [result.message.id])
  end

  test 'automação de outro cliente não envia' do
    evolution!
    other = Client.create!(name: 'Outra', email: "o-#{SecureRandom.hex(4)}@example.com")
    assert_no_difference 'Whatsapp::Message.count' do
      result = Whatsapp::Outbound.deliver(client: other, automation: @automation, phone: '11999990000', body: 'oi')
      assert_not result.ok
      assert_equal 'automação de outro cliente', result.error
    end
  end

  test 'telefone inválido retorna falha em vez de levantar' do
    evolution!
    result = Whatsapp::Outbound.deliver(client: @client, automation: @automation, phone: 'abc', body: 'oi')
    assert_not result.ok
    assert_equal 'telefone inválido', result.error
  end
end
