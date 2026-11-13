class AutomationActionsController < ApplicationController
  include ClientScoped

  before_action :authenticate_user!
  before_action :set_client
  before_action :require_client!
  before_action :set_automation

  def index
    @automation_actions = @automation.automation_actions
                                     .includes(:customer, :order)
                                     .order(created_at: :desc)
                                     .paginate(page: params[:page], per_page: 20)

    if params[:action_status].present?
      @automation_actions = @automation_actions.where(kind: params[:action_status])
    end

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @automation_actions = @automation_actions.joins(:customer).where('customers.name ILIKE ? OR customers.email ILIKE ?',
                                                                       search_term, search_term)
    end
  end

  def resend
    automation_action = @automation.automation_actions.friendly.find(params[:id])

    SendAutomationNotificationJob.perform_later(automation_action.id)

    redirect_to automation_actions_path(@automation), notice: 'Reenvio agendado com sucesso.'
  rescue ActiveRecord::RecordNotFound
    redirect_to automations_path, alert: 'Notificação não encontrada.'
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

  def set_automation
    @automation = current_client.automations.friendly.find(params[:automation_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to automations_path, alert: 'Automação não encontrada.'
  end
end
