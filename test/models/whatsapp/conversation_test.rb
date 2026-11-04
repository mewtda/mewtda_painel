require 'test_helper'

class Whatsapp::ConversationTest < ActiveSupport::TestCase
  def setup
    @client = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    @connection = @client.whatsapp_connections.create!(name: 'A1')
    @contact = @connection.contacts.create!(provider_jid: '5511999999999@s.whatsapp.net', phone: '+5511999999999')
    @conversation = @connection.conversations.create!(contact: @contact)
  end

  test 'team_replied! pausa a resposta automática' do
    @conversation.update!(state: 'closed')
    @conversation.team_replied!

    @conversation.reload
    assert_equal 'open', @conversation.state
    assert @conversation.auto_reply_paused
  end

  test 'customer_wrote! reabre conversa encerrada' do
    @conversation.update!(state: 'closed')
    @conversation.customer_wrote!

    assert_equal 'open', @conversation.reload.state
  end

  test 'contato de outro número é inválido' do
    other = @client.whatsapp_connections.create!(name: 'A2')
    foreign = other.contacts.create!(provider_jid: '5511888888888@s.whatsapp.net')
    conversation = @connection.conversations.new(contact: foreign)

    refute conversation.valid?
    assert conversation.errors[:contact].any?
  end
end
