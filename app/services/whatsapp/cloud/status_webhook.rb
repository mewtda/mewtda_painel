module Whatsapp
  module Cloud
    # Status das mensagens que a Meta manda pelo webhook da API Oficial (field "messages", value.statuses):
    # sent → delivered → read, ou failed com o código e o motivo. Atualiza o checkout da recuperação de
    # carrinho ou o destinatário de campanha pelo id da mensagem (wamid). Ids desconhecidos são ignorados.
    module StatusWebhook
      RANK = { 'sent' => 1, 'delivered' => 2, 'read' => 3, 'failed' => 4 }.freeze

      module_function

      def process(payload)
        statuses(payload).each { |status| apply(status) }
      end

      def statuses(payload)
        Array(payload['entry']).flat_map { |entry| Array(entry['changes']) }
                               .flat_map { |change| Array(change.dig('value', 'statuses')) }
                               .select { |status| status['id'].present? && RANK.key?(status['status']) }
      end

      def apply(status)
        name = status['status']
        at = Time.zone.at(status['timestamp'].to_i) if status['timestamp'].present?
        error = error_text(status['errors'])

        checkout = AbandonedCheckout.find_by(whatsapp_message_id: status['id'])
        if checkout && advance?(checkout.whatsapp_status, name)
          checkout.update_columns(whatsapp_status: name, whatsapp_status_at: at || Time.current, whatsapp_error: error)
        end

        recipient = CampaignRecipient.find_by(provider_message_id: status['id'])
        return unless recipient && advance?(recipient.delivery_status, name)

        recipient.update_columns(delivery_status: name, delivery_status_at: at || Time.current, delivery_error: error)
      end

      # A Meta pode mandar fora de ordem: só avança (lida não volta para entregue); falha sempre vale.
      def advance?(current, incoming)
        incoming == 'failed' || RANK.fetch(incoming) > RANK.fetch(current.to_s, 0)
      end

      def error_text(errors)
        error = Array(errors).first
        return if error.blank?

        details = error.dig('error_data', 'details')
        ["#{error['code']}: #{error['title'] || error['message']}", details].compact_blank.uniq.join(' — ').truncate(250)
      end
    end
  end
end
