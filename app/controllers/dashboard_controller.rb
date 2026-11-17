# frozen_string_literal: true

class DashboardController < ApplicationController
  include ClientScoped

  before_action :authenticate_user!
  before_action :set_client
  before_action :load_form_references, only: [:index]

  def index
    @insight = @client&.conversion_insights&.latest_first&.first
  end

  def session_detail
    return render json: { error: 'Sem cliente' }, status: :unprocessable_entity unless @client

    events = ShopifyEvent
             .where(client_id: @client.id, session_id: params[:session_id])
             .order(:created_at)

    render json: {
      session_id: params[:session_id],
      shop_domain: events.first&.shop_domain,
      started_at: events.first&.created_at,
      last_at: events.last&.created_at,
      event_count: events.count,
      events: events.map do |e|
        {
          id: e.id,
          kind: e.kind,
          event_name: e.event_name,
          event_type: e.event_type,
          event_id: e.event_id,
          created_at: e.created_at,
          data: e.data,
          context: e.context
        }
      end
    }
  end

  private

  def load_form_references
    @period = params[:period].presence || "1"
    @filter_year  = params[:year].presence&.to_i
    @filter_month = params[:month].presence&.to_i

    unless @client
      @empty_state = true
      return
    end

    # Os eventos do pixel são muitos e as consultas demoram: a tela abre vazia
    # e só carrega depois que o usuário escolhe o período.
    if params[:period].blank? && (@filter_year.blank? || @filter_month.blank?)
      @period = nil
      @empty_state = true
      @awaiting_period = true
      return
    end

    @using_month_filter = @filter_year.present? && @filter_month.present?

    # O relatório roda no TrackingReportJob e volta pelo TrackingReportChannel
    # (websocket). O token assinado diz ao canal qual relatório gerar e pra quem.
    @report_token = Tracking::ReportToken.generate(
      user: current_user, client: @client, period: @period, year: @filter_year, month: @filter_month
    )
  end
end
