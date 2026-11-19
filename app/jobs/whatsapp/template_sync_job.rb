module Whatsapp
  # Atualiza a cada 10 minutos o status dos modelos em análise na Meta.
  class TemplateSyncJob < ApplicationJob
    queue_as :default

    def perform
      Client.where(id: client_ids).find_each do |client|
        next unless Whatsapp::Cloud::Api.new(client).configured?

        Whatsapp::Cloud::TemplateSync.new(client).call
      rescue Whatsapp::Cloud::Api::Error => e
        Rails.logger.warn("[WhatsappTemplateSync] cliente #{client.id}: #{e.message}")
      end
    end

    private

    # Modelos em análise, e também os aprovados de clientes com mensagens de WhatsApp para enviar
    # (a Meta pode pausar ou desativar um modelo aprovado).
    def client_ids
      pending = WhatsappTemplate.where(status: 'pending').select(:client_id)
      in_use = Campaign.where(id: CampaignMessage.where(channel: 'whatsapp', status: CampaignMessage::RUNNABLE)
                                                 .select(:campaign_id)).select(:client_id)
      Client.where(id: pending).or(Client.where(id: in_use)).select(:id)
    end
  end
end
