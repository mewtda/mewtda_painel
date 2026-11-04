require 'test_helper'

class Whatsapp::AutoReplyJobTest < ActiveJob::TestCase
  JID = '5511988887777@s.whatsapp.net'.freeze

  class FakeChat
    attr_reader :calls, :last_messages

    def initialize(result = 'Claro!', &during)
      @calls = 0
      @result = result
      @during = during
    end

    def reply(messages:)
      @calls += 1
      @last_messages = messages
      @during&.call
      raise Openai::Chat::Error, 'falhou' if @result == :error

      @result
    end
  end

  def setup
    @client = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_provider: 'evolution', auto_reply_enabled: true, openai_api_key: 'sk-x',
                             openai_model: 'gpt-x', auto_reply_instructions: 'Loja de roupas.')
    @connection = @client.whatsapp_connections.create!(name: 'A1', state: 'connected')
    contact = @connection.contacts.create!(provider_jid: JID, phone: '+5511988887777')
    @conversation = @connection.conversations.create!(contact: contact)
  end

  def incoming(body, historical: false)
    @conversation.messages.create!(connection: @connection, direction: 'incoming', kind: 'text', body: body,
                                   state: 'received', sent_at: Time.current, historical: historical)
  end

  def run_job(message, chat)
    Openai::Chat.stub(:new, ->(**) { chat }) { Whatsapp::AutoReplyJob.perform_now(@conversation.id, message.id) }
  end

  test 'rajada: só a última mensagem chama a OpenAI, uma vez' do
    chat = FakeChat.new
    m1, m2, m3 = incoming('a'), incoming('b'), incoming('c')
    run_job(m1, chat)
    run_job(m2, chat)
    assert_equal 0, chat.calls
    assert_enqueued_jobs 0, only: Whatsapp::SendJob
    run_job(m3, chat)

    assert_equal 1, chat.calls
    reply = @conversation.messages.find_by(origin: 'ai')
    assert_equal 'Claro!', reply.body
    assert_equal 'queued', reply.state
    assert_equal 'outgoing', reply.direction
    assert_equal "ai-#{m3.id}", reply.client_nonce
    assert_enqueued_with(job: Whatsapp::SendJob, args: [reply.id])
  end

  test 'equipe responde durante a chamada: resposta velha não é criada' do
    chat = FakeChat.new { @conversation.update!(auto_reply_paused: true) }
    run_job(incoming('oi'), chat)
    assert_equal 1, chat.calls
    assert_equal 0, @conversation.messages.where(origin: 'ai').count
    assert_enqueued_jobs 0, only: Whatsapp::SendJob
  end

  test 'cliente escreve durante a chamada: resposta velha não é criada' do
    chat = FakeChat.new { incoming('mais uma') }
    run_job(incoming('oi'), chat)
    assert_equal 0, @conversation.messages.where(origin: 'ai').count
    assert_enqueued_jobs 0, only: Whatsapp::SendJob
  end

  test 'conversa pausada não chama a OpenAI' do
    @conversation.update!(auto_reply_paused: true)
    chat = FakeChat.new
    run_job(incoming('oi'), chat)
    assert_equal 0, chat.calls
  end

  test 'mesma mensagem processada duas vezes gera uma resposta' do
    chat = FakeChat.new
    m = incoming('oi')
    2.times { run_job(m, chat) }
    assert_equal 1, chat.calls
    assert_equal 1, @conversation.messages.where(origin: 'ai').count
  end

  test 'erro da OpenAI não cria mensagem nem reenvia' do
    chat = FakeChat.new(:error)
    run_job(incoming('oi'), chat)
    assert_equal 0, @conversation.messages.where(origin: 'ai').count
    assert_enqueued_jobs 0, only: Whatsapp::SendJob
  end

  test 'prompt inclui instruções, regra fixa, checkout e histórico' do
    @client.abandoned_checkouts.create!(whatsapp_conversation_id: @conversation.id, total_price: 99.9,
                                        recovery_url: 'https://loja/rec', first_coupon_code: 'VOLTA10',
                                        line_items: [{ 'title' => 'Biquíni', 'quantity' => 2 }],
                                        shopify_checkout_id: 'c1', shopify_checkout_token: 'tok1', phone: '+5511988887777')
    chat = FakeChat.new
    incoming('oi')
    run_job(incoming('quero comprar'), chat)

    system = chat.last_messages.first
    assert_equal 'system', system[:role]
    assert_includes system[:content], 'Loja de roupas.'
    assert_includes system[:content], 'Nunca invente'
    assert_includes system[:content], 'Biquíni'
    assert_includes system[:content], 'https://loja/rec'
    assert_includes system[:content], 'VOLTA10'
    assert_equal %w[user user], chat.last_messages.drop(1).map { |m| m[:role] }
  end

  test 'schedule não enfileira com auto reply desligado, pausada ou contato não individual' do
    message = incoming('oi')
    @client.update!(auto_reply_enabled: false)
    Whatsapp::AutoReplyJob.schedule(@conversation, message)
    assert_enqueued_jobs 0

    @client.update!(auto_reply_enabled: true)
    @conversation.update!(auto_reply_paused: true)
    Whatsapp::AutoReplyJob.schedule(@conversation, message)
    assert_enqueued_jobs 0

    @conversation.update!(auto_reply_paused: false)
    @conversation.contact.update!(provider_jid: '120363000000000000@g.us')
    Whatsapp::AutoReplyJob.schedule(@conversation, message)
    assert_enqueued_jobs 0
  end

  test 'schedule enfileira com 20 segundos de espera quando pronto' do
    message = incoming('oi')
    Whatsapp::AutoReplyJob.schedule(@conversation, message)
    assert_enqueued_with(job: Whatsapp::AutoReplyJob, args: [@conversation.id, message.id])
    assert_in_delta 20, enqueued_jobs.first[:at] - Time.now.to_f, 3
  end

  test 'erro inesperado não propaga nem reenfileira' do
    m = incoming('oi')
    boom = Object.new
    boom.define_singleton_method(:reply) { |**| raise 'inesperado' }
    assert_nothing_raised { run_job(m, boom) }
    assert_equal 0, @conversation.messages.where(origin: 'ai').count
  end
end
