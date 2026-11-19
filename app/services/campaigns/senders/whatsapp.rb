module Campaigns
  module Senders
    # Envia o modelo aprovado de WhatsApp pela API Oficial (Cloud API). {{1}} = primeiro nome ou "cliente".
    # deliver devolve :sent, :failed, :blocked ou [:pause | :wait, Time] (para o lote sem marcar a pessoa).
    class Whatsapp
      RATE_LIMIT_WAIT = 1.minute

      def initialize(message)
        @message = message
        @client = message.campaign.client
      end

      def channel = 'whatsapp'

      def blocker
        template = message.whatsapp_template&.reload
        return ['O modelo de WhatsApp desta mensagem foi excluído. Escolha outro e confirme de novo.', nil] unless template
        unless api.configured?
          return ['A API Oficial do WhatsApp da loja não está configurada. Tentamos de novo em 1 hora.', 1.hour.from_now]
        end
        unless template.approved?
          return ["O modelo \"#{template.label}\" não está aprovado pela Meta (#{template.status_label.downcase}). " \
                  'Tentamos de novo em 1 hora.', 1.hour.from_now]
        end

        nil
      end

      def address(profile) = ::Whatsapp::Phone.normalize(profile.phone)

      def deliver(recipient)
        return [:pause, message.resume_at] if Billing::Usage.new(client).limit_reached?('whatsapp')

        template = message.whatsapp_template
        params = template.uses_variable? ? [recipient.name.to_s.split.first.presence || 'cliente'] : []
        id = api.send_template(to: recipient.phone, name: template.name, language: template.language, body_params: params)
        recipient.update!(status: 'sent', sent_at: Time.current, provider_message_id: id)
        :sent
      rescue ::Whatsapp::Cloud::Api::RateLimited
        [:wait, Time.current + RATE_LIMIT_WAIT]
      rescue ::Whatsapp::Cloud::Api::Paused => e
        template.update_columns(status: 'paused', updated_at: Time.current) if e.template_problem?
        [:pause, 1.hour.from_now, "A Meta recusou o envio: #{e.message}. Tentamos de novo em 1 hora."]
      rescue ::Whatsapp::Cloud::Api::Blocked => e
        recipient.update!(status: 'blocked', error: e.message.to_s.first(250))
        :blocked
      rescue ::Whatsapp::Cloud::Api::NotConfigured
        [:pause, 1.hour.from_now, 'A API Oficial do WhatsApp da loja não está configurada. Tentamos de novo em 1 hora.']
      rescue ::Whatsapp::Cloud::Api::Error => e
        # Sem código = a Meta não respondeu (rede/timeout): espera e tenta de novo, sem marcar a pessoa.
        return [:wait, Time.current + RATE_LIMIT_WAIT] if e.code.nil?

        recipient.update!(status: 'failed', error: e.message.to_s.first(250))
        :failed
      end

      private

      attr_reader :message, :client

      def api = @api ||= ::Whatsapp::Cloud::Api.new(client)
    end
  end
end
