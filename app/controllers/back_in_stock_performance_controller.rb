class BackInStockPerformanceController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :require_setting!

  def show
    @period = Campaigns::Period.from_params(params)
    @result = BackInStock::Performance.new(@client, @period, sort: params[:ordem]).call
  end

  def export
    sheet = Spreadsheets::BackInStockAlerts.new(@client, Campaigns::Period.from_params(params))
    send_data sheet.to_xlsx, filename: sheet.filename, type: sheet.content_type
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def require_setting!
    redirect_to back_in_stock_path unless @client.back_in_stock_setting
  end
end
