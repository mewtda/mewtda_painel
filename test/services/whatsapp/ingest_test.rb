require 'test_helper'

class Whatsapp::IngestTest < ActiveSupport::TestCase
  JID = '5511988887777@s.whatsapp.net'.freeze

  def setup
    @client = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    @connection = @client.whatsapp_connections.create!(name: 'A1', state: 'connected')
    @ingest = Whatsapp::Ingest.new(@connection)
  end

  def wa_message(id, from_me: false, message: { 'conversation' => 'Olá' })
    { 'key' => { 'id' => id, 'remoteJid' => JID, 'fromMe' => from_me }, 'pushName' => 'Maria',
      'message' => message, 'messageTimestamp' => Time.current.to_i }
  end

  test 'mensagem recebida cria contato, conversa e mensagem incoming' do
    message = @ingest.message!(wa_message('in-1'))

    assert_equal 1, @connection.contacts.count
    assert_equal 1, @connection.conversations.count
    assert_equal 'incoming', message.direction
    assert_equal 'received', message.state
    assert_equal 'Olá', message.body
    assert_equal 'Maria', message.conversation.contact.name
    assert_equal '+5511988887777', message.conversation.contact.phone
  end

  test 'mesmo key.id duas vezes gera uma só mensagem' do
    2.times { @ingest.message!(wa_message('dup')) }

    assert_equal 1, @connection.messages.where(provider_id: 'dup').count
  end

  test 'videoMessage vira kind video com mídia pendente' do
    message = @ingest.message!(wa_message('vid', message: { 'videoMessage' => { 'caption' => 'veja', 'fileLength' => 1000 } }))

    assert_equal 'video', message.kind
    assert_equal 'pending', message.media_state
    assert_equal 'veja', message.body
  end

  test 'stickerMessage vira kind sticker' do
    message = @ingest.message!(wa_message('stk', message: { 'stickerMessage' => { 'fileLength' => 100 } }))

    assert_equal 'sticker', message.kind
    assert_equal 'pending', message.media_state
  end

  test 'mensagem enviada pelo celular vira origin phone e pausa a resposta automática' do
    message = @ingest.message!(wa_message('phone-1', from_me: true))

    assert_equal 'outgoing', message.direction
    assert_equal 'phone', message.origin
    assert message.conversation.reload.auto_reply_paused
  end

  test 'mensagem recebida agenda a resposta automática' do
    scheduled = []
    Whatsapp::AutoReplyJob.stub(:schedule, ->(conversation, message) { scheduled << [conversation, message] }) do
      @ingest.message!(wa_message('in-2'))
    end

    assert_equal 1, scheduled.size
  end
end
