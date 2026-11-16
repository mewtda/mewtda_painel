class CustomAutomationsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_automations
  before_action :set_run, only: [:show, :spreadsheet, :emit, :discard]

  def index
    @routines = CustomAutomations::Registry.routines_for(@client)
    @runs = CustomAutomationRun.where(client: @client).recent.limit(50)
  end

  # Rotinas automáticas já rodam pelo Scheduler; aqui só adianta a próxima.
  def run_routine
    kind = params[:kind].to_s
    unless CustomAutomations::Registry.routines_for(@client).key?(kind)
      return redirect_to(custom_automations_path,
                         alert: 'Rotina indisponível para este cliente.')
    end

    CustomAutomations::RoutineJob.perform_later(kind, @client.id)
    redirect_to custom_automations_path, notice: 'Rotina enfileirada — roda em instantes.'
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
      redirect_to custom_automations_path, notice: notice
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
  end

  def set_run
    @run = CustomAutomationRun.where(client: @client).find(params[:id])
  end

  def run_params
    params.require(:custom_automation_run).permit(:kind, :period_start, :period_end, :order_filter, :price_percentage)
  end
end
