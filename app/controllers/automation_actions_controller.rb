class CampaignsController < ApplicationController
  include ClientScoped

  before_action :authenticate_user!
  before_action :set_client
  before_action :require_client!
  # A criação livre de campanhas foi substituída pelas Automações (telas
  # dedicadas por tipo). show/resend_action continuam ativos porque são
  # usados pelo botão "Ver Dados" de cada automação.
  before_action :redirect_deactivated!, only: %i[index new create edit update destroy]
  before_action :set_campaign, only: %i[show edit update destroy]

  def index
    @campaigns = current_client.campaigns
                               .order(created_at: :desc)
                               .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @campaigns = @campaigns.where('name ILIKE ?', search_term)
    end

    if params[:status].present?
      case params[:status]
      when 'active'
        @campaigns = @campaigns.where(active: true)
      when 'inactive'
        @campaigns = @campaigns.where(active: false)
      when 'running'
        @campaigns = @campaigns.active.where('start_date <= ? AND end_date >= ?', Date.current, Date.current)
      end
    end

    if params[:kind].present?
      @campaigns = @campaigns.where(kind: params[:kind])
    end
  end

  def show
    @campaign_actions = @campaign.campaign_actions
                                 .includes(:customer, :order)
                                 .order(created_at: :desc)
                                 .paginate(page: params[:page], per_page: 20)

    if params[:action_status].present?
      @campaign_actions = @campaign_actions.where(kind: params[:action_status])
    end

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @campaign_actions = @campaign_actions.joins(:customer).where('customers.name ILIKE ? OR customers.email ILIKE ?',
                                                                   search_term, search_term)
    end
  end

  def new
    @campaign = current_client.campaigns.new
    @campaign.days_after_purchase = 7
    @campaign.start_date = Date.current
    @campaign.end_date = Date.current + 30.days
  end

  def create
    @campaign = current_client.campaigns.new(campaign_params)
    if @campaign.save
      redirect_to campaigns_path, notice: 'Campanha criada com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @campaign.update(campaign_params)
      redirect_to campaigns_path, notice: 'Campanha atualizada com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @campaign.destroy
    redirect_to campaigns_path, notice: 'Campanha excluída com sucesso.'
  end

  def resend_action
    campaign = current_client.campaigns.friendly.find(params[:campaign_id])
    campaign_action = campaign.campaign_actions.friendly.find(params[:action_id])

    SendCampaignNotificationJob.perform_later(campaign_action.id)

    redirect_to campaign_path(campaign), notice: 'Reenvio agendado com sucesso.'
  rescue ActiveRecord::RecordNotFound
    redirect_to campaigns_path, alert: 'Notificação não encontrada.'
  end

  private

  def current_client
    @client
  end
  helper_method :current_client

  def require_client!
    unless @client
      redirect_to crm_path, alert: 'Nenhum cliente selecionado.'
    end
  end

  def redirect_deactivated!
    redirect_to automations_path, notice: 'Campanhas foi substituído pelas Automações.'
  end

  def set_campaign
    @campaign = current_client.campaigns.friendly.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to campaigns_path, alert: 'Campanha não encontrada.'
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :kind, :message, :days_after_purchase, :start_date, :end_date, :active,
      :filter_inactive_days, :filter_min_orders, :filter_product_name, :filter_maderite,
      :max_sends, :interval_days
    )
  end
end
