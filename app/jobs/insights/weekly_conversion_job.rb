module Insights
  # Roda todo dia pelo Heroku Scheduler e gera, uma vez por semana, o insight
  # de conversão de cada cliente ativo com eventos de pixel na semana. Quem já
  # tem o insight da semana é pulado, então rodar de novo não gasta API.
  class WeeklyConversionJob < ApplicationJob
    queue_as :default

    def perform
      unless ENV['ANTHROPIC_API_KEY'].present?
        Rails.logger.warn('[Insights::WeeklyConversionJob] ANTHROPIC_API_KEY não configurada — nada a fazer.')
        return
      end

      week_start = Time.zone.today.beginning_of_week
      done = ConversionInsight.where(week_start: week_start).select(:client_id)
      active = ShopifyEvent.where(created_at: 7.days.ago..).select(:client_id)

      Client.where(active: true, id: active).where.not(id: done).find_each do |client|
        WeeklyConversion.new(client).call
      rescue Anthropic::Errors::APIError => e
        Rails.logger.error("[Insights::WeeklyConversionJob] client #{client.id}: #{e.class} #{e.message}")
      end
    end
  end
end
