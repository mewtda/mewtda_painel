module Spreadsheets
  class Customers < Base
    HEADERS = ['Nome', 'E-mail', 'Telefone', 'Cidade', 'UF', 'Nº de compras', 'Total gasto', 'Ticket médio',
               'Primeira compra', 'Última compra', 'Valor da última compra', 'Perfil RFM',
               'Marketing por e-mail'].freeze

    def self.row(profile)
      [profile.name, profile.email, profile.phone, profile.city, profile.state, profile.orders_count,
       profile.total_spent.to_f, profile.avg_ticket.to_f, profile.first_order_at&.strftime('%d/%m/%Y'),
       profile.last_order_at&.strftime('%d/%m/%Y'), profile.last_order_total&.to_f, profile.rfm_label,
       Segments::Rules::MARKETING_STATES.fetch(profile.email_marketing_state || 'unknown')]
    end

    def initialize(profiles)
      super()
      @profiles = profiles
    end

    def filename = "clientes_#{stamp}.xlsx"

    private

    attr_reader :profiles

    def sheet_name = 'Clientes'
    def headers = HEADERS
    def rows = profiles.order(:name).map { |profile| self.class.row(profile) }
  end
end
