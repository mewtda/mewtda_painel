# Insight semanal sobre a conversão do site do cliente, escrito pelo Claude a
# partir dos últimos 7 dias do pixel (Insights::WeeklyConversion). Um por
# cliente e semana; a tela principal mostra o mais recente.
class ConversionInsight < ApplicationRecord
  belongs_to :client

  validates :week_start, :body, presence: true

  scope :latest_first, -> { order(week_start: :desc) }
end
