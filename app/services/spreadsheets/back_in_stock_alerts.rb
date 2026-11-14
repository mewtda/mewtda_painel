module Spreadsheets
  class BackInStockAlerts < Base
    HEADERS = ['Produto', 'Variação', 'SKU', 'E-mail', 'Telefone', 'Status', 'Solicitado em', 'Avisado em',
               'Cancelado em'].freeze
    STATUSES = { 'pending' => 'Esperando', 'notified' => 'Notificado', 'cancelled' => 'Cancelado' }.freeze

    def initialize(client, period)
      super()
      @client = client
      @period = period
    end

    def filename = "de_volta_ao_estoque_#{stamp}.xlsx"

    private

    attr_reader :client, :period

    def sheet_name = 'Solicitações'
    def headers = HEADERS

    def rows
      client.back_in_stock_alerts.where(created_at: period.time_range).order(created_at: :desc).map do |alert|
        [alert.product_title, alert.variant_title, alert.sku, alert.email, alert.phone, STATUSES.fetch(alert.status),
         time(alert.created_at), time(alert.notified_at), time(alert.cancelled_at)]
      end
    end

    def time(value) = value&.strftime('%d/%m/%Y %H:%M')
  end
end
