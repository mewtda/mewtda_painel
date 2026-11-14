class CampaignPerformanceController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!

  def show
    @period = Campaigns::Period.from_params(params)
    @campaign = @client.campaigns.find_by(id: params[:campanha]) if params[:campanha].present?
    @campaign_options = @client.campaigns.where.not(started_at: nil).order(started_at: :desc)
    @result = Campaigns::Performance.new(scope).call
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def scope
    campaigns = @client.campaigns.where.not(started_at: nil)
    campaigns = campaigns.where(channel: params[:canal]) if params[:canal].in?(Campaign::CHANNELS.keys)
    @campaign ? campaigns.where(id: @campaign.id) : campaigns.where(started_at: @period.time_range)
  end
end
