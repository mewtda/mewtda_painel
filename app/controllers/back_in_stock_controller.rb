class BackInStockController < ApplicationController
  include ClientScoped

  GROUPS_PER_PAGE = 20
  SEARCH_MAX_LENGTH = 100
  SUMMARY_MONTHS = 12

  before_action :set_client
  before_action :require_client!
  before_action :set_setting
  before_action :require_setting!, only: %i[update regenerate_token cancel_alert]
  before_action :load_alerts, only: %i[show update]
  before_action :load_summary, only: %i[show update]
  before_action :load_email_template, only: %i[show update]

  def show; end

  def create
    @setting ||= @client.create_back_in_stock_setting!
    redirect_to back_in_stock_path(anchor: 'instalacao'), notice: 'De volta ao estoque ativado. Agora instale o script na loja.'
  end

  def update
    if @setting.update(setting_params)
      redirect_to back_in_stock_path(anchor: 'configuracoes'), notice: 'Configurações salvas.'
    else
      render :show, status: :unprocessable_entity
    end
  end

  def regenerate_token
    @setting.regenerate_public_token
    redirect_to back_in_stock_path(anchor: 'instalacao'), notice: 'Novo token gerado. Atualize o script na loja.'
  end

  def cancel_alert
    @client.back_in_stock_alerts.pending.find(params[:alert_id]).cancelled!
    redirect_to back_in_stock_path(anchor: 'alertas'), notice: 'Alerta cancelado.'
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_setting
    @setting = @client.back_in_stock_setting
  end

  def require_setting!
    redirect_to back_in_stock_path unless @setting
  end

  def load_alerts
    return unless @setting

    alerts = @client.back_in_stock_alerts
    filtered = alerts.where(status: selected_status).search(search_term)

    @filters = { status: selected_status, q: search_term, sort: selected_sort }
    @status_counts = alerts.group(:status).count
    @pending_value = alerts.pending.sum(:price)
    @pending_variants = alerts.pending.distinct.count(:shopify_variant_id)
    @groups = paginated_groups(filtered)
    @contacts = filtered.where(shopify_variant_id: @groups.map(&:shopify_variant_id)).contacts_by_variant
  end

  def load_summary
    return unless @setting

    counts = @client.back_in_stock_alerts.notified_by_month(SUMMARY_MONTHS.months.ago.beginning_of_month)
    months = SUMMARY_MONTHS.times.map { |index| Date.current.beginning_of_month - index.months }
    @notified_by_month = months.index_with { |month| counts.fetch(month, 0) }
  end

  def load_email_template
    @email_template = @setting&.email_template
  end

  def paginated_groups(alerts)
    alerts.grouped_by_variant(selected_sort)
          .paginate(page: params[:page], per_page: GROUPS_PER_PAGE,
                    total_entries: alerts.distinct.count(:shopify_variant_id))
  end

  def selected_status
    params[:status].presence_in(BackInStockAlert.statuses.keys) || 'pending'
  end

  def selected_sort
    params[:sort].presence_in(BackInStockAlert::SORTS.keys) || 'demand'
  end

  def search_term
    params[:q].to_s.strip.first(SEARCH_MAX_LENGTH).presence
  end

  def setting_params
    params.require(:back_in_stock_setting).permit(:active, :only_marked_products, :button_text, :modal_title, :accent_color)
  end
end
