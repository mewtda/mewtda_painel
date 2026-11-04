module Whatsapp
  # Resposta automática (OpenAI). A mensagem mais nova de uma rajada responde por todas.
  class AutoReplyJob < ApplicationJob
    queue_as :whatsapp

    RULES = 'Responda em português, de forma curta, como atendente da loja. ' \
            'Nunca invente preços, prazos ou cupons que não estejam no contexto.'.freeze
    HISTORY = 20

    def self.schedule(conversation, message)
      return unless conversation.connection.client.auto_reply_ready?
      return if conversation.auto_reply_paused?
      return unless Phone.individual_jid?(conversation.contact.provider_jid)

      set(wait: 20.seconds).perform_later(conversation.id, message.id)
    end

    def perform(conversation_id, message_id)
      conversation = Conversation.find_by(id: conversation_id)
      return unless conversation

      client = conversation.connection.client
      return if stale?(conversation, message_id)

      nonce = "ai-#{message_id}"
      return if conversation.messages.exists?(origin: 'ai', client_nonce: nonce)

      text = Openai::Chat.new(api_key: client.openai_api_key, model: client.openai_model)
                         .reply(messages: prompt(client, conversation))
      # A chamada leva até 30 s: a equipe pode ter respondido ou o cliente escrito de novo.
      return if stale?(conversation.reload, message_id)

      reply = conversation.messages.create!(connection: conversation.connection, direction: 'outgoing',
                                            kind: 'text', origin: 'ai', body: text, state: 'queued',
                                            client_nonce: nonce, sent_at: Time.current)
      SendJob.perform_later(reply.id)
    rescue Openai::Chat::Error => e
      Rails.logger.warn("whatsapp auto reply #{conversation_id}: #{e.message}")
    rescue ActiveRecord::RecordNotUnique
      nil # outra execução já respondeu a esta mensagem
    end

    private

    def stale?(conversation, message_id)
      !conversation.connection.client.reload.auto_reply_ready? || conversation.auto_reply_paused? ||
        conversation.messages.where(direction: 'incoming', historical: false).where('id > ?', message_id).exists?
    end

    def prompt(client, conversation)
      [{ role: 'system', content: system_prompt(client, conversation) }] + history(conversation)
    end

    def history(conversation)
      conversation.messages.where(kind: 'text').where.not(body: [nil, '']).order(id: :desc).limit(HISTORY).reverse
                  .map { |m| { role: m.direction == 'incoming' ? 'user' : 'assistant', content: m.body } }
    end

    def system_prompt(client, conversation)
      [client.auto_reply_instructions, RULES, checkout_context(conversation)].compact.join("\n\n")
    end

    def checkout_context(conversation)
      checkout = AbandonedCheckout.where(whatsapp_conversation_id: conversation.id).order(:id).last
      return unless checkout

      items = Array(checkout.line_items).map do |item|
        item = item.with_indifferent_access
        [item[:title], ("x#{item[:quantity]}" if item[:quantity]), (item[:price] && "(#{item[:price]})")].compact.join(' ')
      end
      coupon = checkout.second_coupon_code.presence || checkout.first_coupon_code.presence
      lines = ['Contexto do carrinho abandonado deste cliente:']
      lines << "Itens: #{items.join(', ')}" if items.any?
      lines << "Total: #{checkout.total_price}" if checkout.total_price
      lines << "Link do carrinho: #{checkout.recovery_url}" if checkout.recovery_url.present?
      lines << "Cupom enviado: #{coupon}" if coupon
      lines.join("\n")
    end
  end
end
