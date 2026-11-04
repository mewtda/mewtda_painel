module Whatsapp
  # Caminho único de envio das automações: Evolution (outbox) ou Z-API, conforme o cliente.
  module Outbound
    Result = Struct.new(:ok, :provider, :connection, :message, :error, keyword_init: true)

    def self.deliver(client:, campaign:, phone:, body:, prefer_connection: nil, strict: false)
      if campaign && campaign.client_id != client.id
        return Result.new(ok: false, provider: client.whatsapp_evolution? ? 'evolution' : 'zapi',
                          error: 'automação de outro cliente')
      end
      return deliver_zapi(client, phone, body) unless client.whatsapp_evolution?

      connection = Router.pick(campaign: campaign, phone: phone, prefer: prefer_connection, strict: strict)
      return Result.new(ok: false, provider: 'evolution', error: 'sem número responsável conectado') unless connection

      message = enqueue(connection, phone, body)
      Result.new(ok: true, provider: 'evolution', connection: connection, message: message)
    end

    def self.deliver_zapi(client, phone, body)
      response = Zapi::Client.new(client).send_text(phone: format_phone(phone), message: body)
      ok = response.is_a?(Hash) && response['zaapId'].present?
      Result.new(ok: ok, provider: 'zapi', error: (ok ? nil : "Falha ao enviar via Z-API: #{response.inspect}"))
    end

    def self.enqueue(connection, phone, body)
      message = nil
      slot = nil
      connection.with_lock do
        now = Time.current
        jid = "#{format_phone(phone)}@s.whatsapp.net"
        contact = Contact.resolve!(connection, { 'remoteJid' => jid })
        conversation = Conversation.find_or_create_by!(connection: connection, contact: contact)
        slot = [connection.next_send_at, now].compact.max
        connection.update!(next_send_at: slot + rand(8..15).seconds)
        message = Message.create!(connection: connection, conversation: conversation, origin: 'automation',
                                  direction: 'outgoing', state: 'queued', kind: 'text', body: body, sent_at: now,
                                  send_after: slot, client_nonce: SecureRandom.hex(16))
        conversation.update!(last_message_at: now, last_message_preview: message.preview.truncate(120))
      end
      # Fora da transação: o worker só pode enxergar a mensagem depois do commit.
      SendJob.set(wait_until: slot).perform_later(message.id)
      message
    end

    def self.format_phone(phone)
      digits = phone.to_s.gsub(/\D/, '')
      digits.start_with?('55') ? digits : "55#{digits}"
    end
    private_class_method :deliver_zapi, :enqueue
  end
end
