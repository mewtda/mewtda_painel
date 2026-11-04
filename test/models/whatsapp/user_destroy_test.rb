require 'test_helper'

class Whatsapp::UserDestroyTest < ActiveSupport::TestCase
  test 'excluir usuário remove leituras e vínculos e mantém as mensagens sem autor' do
    client = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    connection = client.whatsapp_connections.create!(name: 'A1')
    contact = connection.contacts.create!(provider_jid: '5511999999999@s.whatsapp.net')
    conversation = connection.conversations.create!(contact: contact)
    user = User.create!(name: 'Fulano', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'senha123456',
                        client: client)
    membership = Whatsapp::Membership.create!(connection: connection, user: user)
    read = Whatsapp::Read.create!(conversation: conversation, user: user)
    message = connection.messages.create!(conversation: conversation, user: user, direction: 'outgoing',
                                          state: 'sent', sent_at: Time.current, body: 'oi')

    user.destroy!

    refute User.exists?(user.id)
    assert_nil message.reload.user_id
    refute Whatsapp::Read.exists?(read.id)
    refute Whatsapp::Membership.exists?(membership.id)
  end
end
