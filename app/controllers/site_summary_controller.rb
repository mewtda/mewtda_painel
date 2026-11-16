# Tela inicial do CRM: resumo de vendas x anúncios do período (Sales::SiteSummary).
class SiteSummaryController < ApplicationController
  include ClientScoped

  before_action :set_client

  def index
    # Links antigos do Trackeamento site (/crm?period=7) continuam funcionando.
    if params[:period].present? || params[:month].present?
      return redirect_to tracking_dashboard_path(request.query_parameters)
    end

    return unless @client

    @summary = Sales::SiteSummary.new(client: @client, preset: params[:p], from: params[:de], to: params[:ate])
  end
end
