require 'test_helper'

class Whatsapp::MessagesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  PNG = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1F\x15\xC4\x89".b

  def setup
    @a = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    @b = Client.create!(name: 'Loja B', email: "b-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'Usuário' }
    @admin = User.create!(name: 'Admin', email: "adm-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                          password_confirmation: 'password123', profile_id: Profile::ADMIN, client: @a)
    @user_a = User.create!(name: 'Ana', email: "ana-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                           password_confirmation: 'password123', profile_id: Profile::USER, client: @a)
    @a1 = @a.whatsapp_connections.create!(name: 'A1', state: 'connected')
    @b1 = @b.whatsapp_connections.create!(name: 'B1', state: 'connected')
    @a1.memberships.create!(user: @user_a)
    @conv_a1 = conversation(@a1, '5511911110001')
    @conv_b1 = conversation(@b1, '5511911110003')
  end

  def conversation(connection, digits)
    contact = connection.contacts.create!(provider_jid: "#{digits}@s.whatsapp.net", phone: "+#{digits}")
    connection.conversations.create!(contact: contact)
  end

  def media_message(conversation)
    message = conversation.messages.create!(connection: conversation.connection, direction: 'incoming', kind: 'image',
                                            state: 'received', sent_at: Time.current, media_state: 'pending')
    Whatsapp::Media.store!(message, StringIO.new(PNG), filename: 'foto.png')
    message
  end

  def messages_path(conversation, suffix = '') = "/crm/whatsapp/conversations/#{conversation.id}/messages#{suffix}"

  test 'POST messages cria mensagem queued da equipe, pausa a resposta automática e enfileira o envio' do
    sign_in @user_a

    assert_enqueued_with(job: Whatsapp::SendJob) do
      post messages_path(@conv_a1), params: { client_nonce: SecureRandom.uuid, body: 'Olá!' }
    end

    assert_response :accepted
    message = @conv_a1.messages.last
    assert_equal 'queued', message.state
    assert_equal 'team', message.origin
    assert_equal 'outgoing', message.direction
    assert_equal @user_a.id, message.user_id
    assert @conv_a1.reload.auto_reply_paused
    assert_equal 'Olá!', @conv_a1.last_message_preview
    assert_equal 'Ana', response.parsed_body['author']
    assert_equal 'team', response.parsed_body['origin']
  end

  test 'POST messages com o mesmo nonce não duplica' do
    sign_in @user_a
    nonce = SecureRandom.uuid
    post messages_path(@conv_a1), params: { client_nonce: nonce, body: 'Olá!' }
    assert_no_difference 'Whatsapp::Message.count' do
      post messages_path(@conv_a1), params: { client_nonce: nonce, body: 'Olá!' }
    end
    assert_response :accepted
  end

  test 'POST messages com anexo guarda a mídia' do
    sign_in @user_a
    file = Rack::Test::UploadedFile.new(StringIO.new(PNG), 'image/png', true, original_filename: 'foto.png')

    post messages_path(@conv_a1), params: { client_nonce: SecureRandom.uuid, file: file }

    assert_response :accepted
    message = @conv_a1.messages.last
    assert_equal 'image', message.kind
    assert_equal 'foto.png', message.media.filename
    assert_equal "/crm/whatsapp/conversations/#{@conv_a1.id}/messages/#{message.id}/attachment",
                 response.parsed_body['media_url']
  end

  test 'POST messages em número sem acesso é 404' do
    Whatsapp::Membership.where(connection_id: @a1.id).delete_all
    sign_in @user_a
    assert_no_difference 'Whatsapp::Message.count' do
      post messages_path(@conv_a1), params: { client_nonce: SecureRandom.uuid, body: 'Olá!' }
    end
    assert_response :not_found
  end

  test 'attachment de mídia de outro cliente é 404' do
    other = media_message(@conv_b1)
    sign_in @admin

    get messages_path(@conv_b1, "/#{other.id}/attachment")
    assert_response :not_found
    # Nem pela conversa do próprio cliente com o ID da mensagem alheia.
    get messages_path(@conv_a1, "/#{other.id}/attachment")
    assert_response :not_found
  end

  test 'attachment de mídia visível é servido inline para imagem' do
    mine = media_message(@conv_a1)
    sign_in @user_a

    get messages_path(@conv_a1, "/#{mine.id}/attachment")

    assert_response :success
    assert_equal 'image/png', response.media_type
    assert_equal PNG, response.body.b
    assert_match(/inline/, response.headers['Content-Disposition'])
  end

  test 'index lista mensagens com origem e autor' do
    @conv_a1.messages.create!(connection: @a1, direction: 'outgoing', state: 'sent', body: 'Oi, tudo bem?',
                              origin: 'ai', sent_at: Time.current)
    sign_in @user_a

    get messages_path(@conv_a1, '.json')

    assert_response :success
    row = response.parsed_body['messages'].last
    assert_equal 'ai', row['origin']
    assert_equal 'Resposta automática', row['author']
  end

  test 'index pagina o histórico com cursor e recusa cursor inválido' do
    51.times do |i|
      @conv_a1.messages.create!(connection: @a1, direction: 'incoming', state: 'received', body: "m#{i}",
                                sent_at: Time.current - (60 - i).minutes)
    end
    sign_in @user_a

    get messages_path(@conv_a1, '.json')
    assert_equal 50, response.parsed_body['messages'].size
    cursor = response.parsed_body['before']
    assert cursor

    get messages_path(@conv_a1, '.json'), params: { before: cursor }
    assert_equal ['m0'], response.parsed_body['messages'].map { |m| m['body'] }

    get messages_path(@conv_a1, '.json'), params: { before: 'nao-e-cursor' }
    assert_response :unprocessable_entity
  end

  test 'retry_send reenfileira só falha confirmada' do
    message = @conv_a1.messages.create!(connection: @a1, user: @user_a, direction: 'outgoing', state: 'failed',
                                        body: 'Oi', sent_at: Time.current)
    sign_in @user_a

    assert_enqueued_with(job: Whatsapp::SendJob) do
      post messages_path(@conv_a1, "/#{message.id}/retry_send")
    end
    assert_response :accepted
    assert_equal 'queued', message.reload.state

    post messages_path(@conv_a1, "/#{message.id}/retry_send")
    assert_response :unprocessable_entity
  end
end
