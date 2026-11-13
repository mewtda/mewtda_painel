module Whatsapp
  class SendJob < ApplicationJob
    queue_as :whatsapp
    def perform(id)
      message = Message.find(id)
      connection = message.connection
      connection.with_lock do
        message.reload
        return unless message.state == 'queued'
        # Agendada: continua na fila; a recuperação reenfileira quando chegar a hora.
        return if message.send_after&.future?
        unless connection.connected? && allowed?(message)
          message.update!(state: 'failed', error_code: 'number_unavailable_or_access_revoked')
          return
        end
        # Limite diário de mensagens do cliente (definido pelo admin no cadastro do cliente).
        if Billing::Usage.new(connection.client).limit_reached?('whatsapp')
          message.update!(state: 'failed', error_code: 'daily_limit_reached')
          return
        end
        message.update!(state: 'sending', attempted_at: Time.current, error_code: nil)
      end
      # Durable sending marker survives a timeout, worker kill or transaction rollback.
      connection.with_lock do
        message.reload
        return unless message.state == 'sending'
        unless connection.connected? && allowed?(message)
          message.update!(state: 'failed', error_code: 'number_unavailable_or_access_revoked')
          return
        end
        response = connection.gateway.send_message(message)
        key = response['key'] || {}
        raise Providers::Evolution::Unavailable, 'missing_message_id' unless key['id'].present? && key['fromMe'] == true
        expected = message.conversation.contact.aliases.pluck(:jid) + [message.conversation.contact.provider_jid]
        raise Providers::Evolution::Unavailable, 'unexpected_recipient' unless expected.any? { |jid| [key['remoteJid'], key['remoteJidAlt']].compact.any? { |returned| Phone.equivalent_jid?(jid, returned) } }
        # Webhook processing holds the same connection lock; the HTTP response binds the
        # outbox record before an echo can create a duplicate.
        Ingest.new(connection).message!(response, outgoing: message)
      end
    rescue Providers::Evolution::NotConfigured
      Message.where(id: id, state: 'sending').update_all(state: 'failed', error_code: 'provider_not_configured')
    rescue StandardError => e
      # Even an HTTP error can occur after WhatsApp accepted a message. Never retry it.
      Message.where(id: id, state: 'sending').update_all(state: 'uncertain', error_code: 'send_result_unknown')
      Rails.logger.warn("whatsapp send #{id}: #{e.class.name}")
    end

    private

    # Cada origem tem sua própria autorização; nenhuma mensagem sai por número de outro cliente.
    def allowed?(message)
      connection = message.connection
      case message.origin
      when 'team' then Connection.visible_to(message.user, client: connection.client).exists?(connection.id)
      when 'automation' then connection.client.whatsapp_evolution?
      when 'ai' then connection.client.auto_reply_ready?
      else false # 'phone' vem do aparelho e nunca entra na fila.
      end
    end
  end
end
