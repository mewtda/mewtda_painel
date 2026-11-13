module Customers
  # Recalcula os perfis de clientes (RFM) — de uma loja ou de todas (cron diário).
  class RefreshProfilesJob < ApplicationJob
    queue_as :default

    def perform(client_id = nil)
      clients = client_id ? Client.where(id: client_id) : Client.where(id: Order.select(:client_id).distinct)
      clients.find_each do |client|
        RefreshProfiles.new(client).call
        Segment.where(client:).find_each(&:recount!)
      rescue StandardError => e
        Rails.logger.error "[Customers::RefreshProfiles] client #{client.id}: #{e.class}: #{e.message}"
      end
    end
  end
end
