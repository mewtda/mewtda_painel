module Whatsapp
  # Atualiza a cada 10 minutos o status dos modelos em análise na Meta.
  class TemplateSyncJob < ApplicationJob
    queue_as :default

    def perform
      Client.where(id: WhatsappTemplate.where(status: 'pending').select(:client_id)).find_each do |client|
        next unless Whatsapp::Cloud::Api.new(client).configured?

        Whatsapp::Cloud::TemplateSync.new(client).call
      rescue Whatsapp::Cloud::Api::Error => e
        Rails.logger.warn("[WhatsappTemplateSync] cliente #{client.id}: #{e.message}")
      end
    end
  end
end
