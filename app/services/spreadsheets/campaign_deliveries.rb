module Spreadsheets
  # Planilha de "Quem recebeu": uma linha por pessoa do público e, para cada mensagem da campanha,
  # a situação do envio e o detalhe (data do envio ou motivo de não ter recebido).
  class CampaignDeliveries < Base
    BATCH = 500

    def initialize(deliveries, profiles)
      super()
      @deliveries = deliveries
      @profiles = profiles
    end

    def filename = "campanha_#{deliveries.campaign.id}_quem_recebeu_#{stamp}.xlsx"

    private

    attr_reader :deliveries, :profiles

    def sheet_name = 'Quem recebeu'

    def headers
      ['Nome', 'E-mail', 'Telefone'] + deliveries.messages.each_with_index.flat_map do |message, index|
        name = "#{index + 1}. #{message.channel_label}: #{message.template_name || 'Modelo excluído'}"
        [name, "#{name} (detalhe)"]
      end
    end

    def rows
      profiles.each_slice(BATCH).flat_map do |batch|
        cells = deliveries.cells_for(batch)
        batch.map do |profile|
          [profile.name, profile.email, profile.phone] +
            cells.fetch(profile.id).flat_map { |cell| [cell.label, detail(cell)] }
        end
      end
    end

    def detail(cell)
      [cell.at&.in_time_zone&.strftime('%d/%m/%Y %H:%M'), cell.detail].compact.join(' · ').presence
    end
  end
end
