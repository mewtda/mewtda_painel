class CustomAutomationsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_automations
  before_action :set_run, only: [:show, :spreadsheet, :emit, :discard]
  before_action :set_routine, only: [:edit_routine, :update_routine, :preview_routine]

  # Uma aba por automação/rotina do cliente; ?tab=<kind> escolhe qual mostrar.
  def index
    @current_tab = @tabs.key?(params[:tab].to_s) ? params[:tab].to_s : @tabs.keys.first
    return unless @automations.key?(@current_tab)

    @runs = CustomAutomationRun.where(client: @client, kind: @current_tab).recent.limit(50)
  end

  # Rotinas automáticas já rodam pelo Scheduler; aqui só adianta a próxima.
  def run_routine
    kind = params[:kind].to_s
    unless CustomAutomations::Registry.routines_for(@client).key?(kind)
      return redirect_to(custom_automations_path,
                         alert: 'Rotina indisponível para este cliente.')
    end

    if CustomAutomations::Registry.routine(kind)[:configurable]
      CustomAutomations::RoutineJob.perform_later(kind, @client.id, true)
      redirect_to edit_routine_custom_automations_path(kind:), notice: 'Enviando agora para a lista de destinatários.'
    else
      CustomAutomations::RoutineJob.perform_later(kind, @client.id)
      redirect_to custom_automations_path(tab: kind), notice: 'Rotina enfileirada — roda em instantes.'
    end
  end

  def edit_routine
    @setting = CustomAutomationSetting.for(@client, @kind)
  end

  def update_routine
    @setting = CustomAutomationSetting.for(@client, @kind)
    @setting.recipients_text = params.dig(:routine, :recipients)
    @setting.low_stock_limit = params.dig(:routine, :low_stock_limit)
    @setting.enabled = params.dig(:routine, :enabled)

    if @setting.save
      redirect_to edit_routine_custom_automations_path(kind: @kind), notice: 'Configuração salva.'
    else
      render :edit_routine, status: :unprocessable_entity
    end
  end

  # Mostra o e-mail como sai hoje, sem enviar (lê o estoque da Shopify na hora).
  def preview_routine
    render html: @routine[:service].constantize.new(@client).to_html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def new
    kind = params[:kind].to_s
    return redirect_to(custom_automations_path, alert: 'Automação indisponível para este cliente.') unless @automations.key?(kind)

    last_month = Date.current.prev_month
    @run = CustomAutomationRun.new(kind: kind, period_start: last_month.beginning_of_month,
                                   period_end: last_month.end_of_month, order_filter: 'paid',
                                   price_percentage: 70)
  end

  def create
    @run = CustomAutomationRun.new(run_params.merge(client: @client, user: current_user, status: 'pending'))

    unless @automations.key?(@run.kind)
      return redirect_to(custom_automations_path, alert: 'Automação indisponível para este cliente.')
    end

    if @run.save
      CustomAutomationBuildJob.perform_later(@run.id)
      redirect_to custom_automation_path(@run), notice: 'Gerando a nota no Tiny — a página atualiza sozinha.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def spreadsheet
    sheet = CustomAutomations::TransferNoteSpreadsheet.new(@run)
    send_data sheet.to_xlsx, filename: sheet.filename,
                             type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  def emit
    # Troca o status atomicamente pra que dois cliques não emitam duas vezes.
    updated = CustomAutomationRun.where(id: @run.id, status: 'awaiting_review')
                                 .where.not(tiny_note_id: nil)
                                 .update_all(status: 'emitting', error_message: nil, updated_at: Time.current)

    if updated == 1
      CustomAutomationEmitJob.perform_later(@run.id)
      redirect_to custom_automation_path(@run), notice: 'Emitindo a nota no Tiny.'
    else
      redirect_to custom_automation_path(@run), alert: 'Esta nota não está aguardando conferência.'
    end
  end

  def discard
    if @run.discardable?
      @run.update!(status: 'discarded')
      notice = 'Execução descartada.'
      notice += ' Exclua também a nota pendente no Tiny da matriz.' if @run.tiny_note_id.present?
      redirect_to custom_automations_path(tab: @run.kind), notice: notice
    else
      redirect_to custom_automation_path(@run), alert: 'Esta execução não pode ser descartada.'
    end
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_automations
    @automations = CustomAutomations::Registry.for_client(@client)
    @routines = CustomAutomations::Registry.routines_for(@client)
    @tabs = @automations.merge(@routines)
  end

  def set_routine
    @kind = params[:kind].to_s
    @routine = CustomAutomations::Registry.routines_for(@client)[@kind]
    return if @routine&.dig(:configurable)

    redirect_to custom_automations_path, alert: 'Rotina indisponível para este cliente.'
  end

  def set_run
    @run = CustomAutomationRun.where(client: @client).find(params[:id])
  end

  def run_params
    params.require(:custom_automation_run).permit(:kind, :period_start, :period_end, :order_filter, :price_percentage)
  end
end
