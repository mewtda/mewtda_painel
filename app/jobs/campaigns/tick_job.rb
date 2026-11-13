module Campaigns
  # Roda a cada minuto e acorda as campanhas que já podem enviar mais um lote.
  class TickJob < ApplicationJob
    queue_as :default

    def perform
      Campaign.where(status: Campaign::RUNNABLE).where(next_run_at: ..Time.current).pluck(:id).each do |id|
        DispatchJob.perform_later(id)
      end
    end
  end
end
