module Whatsapp
  module Cloud
    # Atualiza status e motivo de rejeição dos modelos do cliente a partir da Meta (casando pelo nome).
    class TemplateSync
      def initialize(client)
        @client = client
      end

      def call
        remote = Api.new(@client).templates.index_by { |t| t['name'] }
        @client.whatsapp_templates.where.not(status: 'draft').find_each do |template|
          data = remote[template.name]
          next unless data

          status = data['status'].to_s.downcase
          template.update_columns(
            status: WhatsappTemplate::STATUSES.include?(status) ? status : template.status,
            meta_id: data['id'].presence || template.meta_id,
            rejection_reason: status == 'rejected' ? data['rejected_reason'].presence : nil,
            synced_at: Time.current, updated_at: Time.current
          )
        end
      end
    end
  end
end
