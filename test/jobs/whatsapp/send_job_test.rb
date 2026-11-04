require 'test_helper'

class Whatsapp::SendJobTest < ActiveJob::TestCase
  JID = '5511988887777@s.whatsapp.net'.freeze

  def setup
    @client = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    @connection = @client.whatsapp_connections.create!(name: 'A1', state: 'connected')
    @user = User.create!(name: 'Fulano', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'senha123456',
                         client: @client)
    Whatsapp::Membership.create!(connection: @connection, user: @user)
    contact = @connection.contacts.create!(provider_jid: JID, phone: '+5511988887777')
    @conversation = @connection.conversations.create!(contact: contact)
    @message = @conversation.messages.create!(connection: @connection, user: @user, direction: 'outgoing',
                                              kind: 'text', body: 'Olá', state: 'queued', sent_at: Time.current)
  end

  def response_for(id = 'sent-1')
    { 'key' => { 'id' => id, 'remoteJid' => JID, 'fromMe' => true }, 'status' => 'PENDING',
      'message' => { 'conversation' => 'Olá' }, 'messageTimestamp' => Time.current.to_i }
  end

  # Gateway real com send_message dublado: nenhum teste toca a rede.
  def with_gateway(send_message)
    gateway = Whatsapp::Providers::Evolution.new(@connection)
    gateway.stub(:send_message, send_message) do
      Whatsapp::Providers::Evolution.stub(:new, gateway) { yield }
    end
  end

  test 'mensagem na fila com número conectado é enviada uma vez' do
    calls = 0
    with_gateway(->(_message) { calls += 1; response_for }) do
      2.times { Whatsapp::SendJob.perform_now(@message.id) }
    end

    assert_equal 1, calls
    @message.reload
    assert_equal 'sent', @message.state
    assert_equal 'sent-1', @message.provider_id
  end

  test 'send_after no futuro não envia e continua na fila' do
    @message.update!(send_after: 10.minutes.from_now)
    calls = 0
    with_gateway(->(_message) { calls += 1; response_for }) { Whatsapp::SendJob.perform_now(@message.id) }

    assert_equal 0, calls
    assert_equal 'queued', @message.reload.state
  end

  test 'número desconectado falha sem chamar o provedor' do
    @connection.update!(state: 'disconnected')
    calls = 0
    with_gateway(->(_message) { calls += 1; response_for }) { Whatsapp::SendJob.perform_now(@message.id) }

    assert_equal 0, calls
    assert_equal 'failed', @message.reload.state
  end

  test 'erro do provedor deixa incerta e nunca reenvia' do
    calls = 0
    with_gateway(->(_message) { calls += 1; raise Whatsapp::Providers::Evolution::Unavailable, 'provider_unavailable' }) do
      2.times { Whatsapp::SendJob.perform_now(@message.id) }
    end

    assert_equal 1, calls
    @message.reload
    assert_equal 'uncertain', @message.state
    assert_equal 'send_result_unknown', @message.error_code
  end

  test 'usuário sem acesso ao número não envia' do
    Whatsapp::Membership.where(user: @user).delete_all
    calls = 0
    with_gateway(->(_message) { calls += 1; response_for }) { Whatsapp::SendJob.perform_now(@message.id) }

    assert_equal 0, calls
    assert_equal 'failed', @message.reload.state
  end

  test 'automação só envia para cliente com Evolution ativo' do
    @message.update!(origin: 'automation', user: nil)
    calls = 0
    with_gateway(->(_message) { calls += 1; response_for }) { Whatsapp::SendJob.perform_now(@message.id) }
    assert_equal 'failed', @message.reload.state

    @client.update!(whatsapp_provider: 'evolution')
    @message.update!(state: 'queued', error_code: nil)
    with_gateway(->(_message) { calls += 1; response_for }) { Whatsapp::SendJob.perform_now(@message.id) }
    assert_equal 1, calls
    assert_equal 'sent', @message.reload.state
  end
end
