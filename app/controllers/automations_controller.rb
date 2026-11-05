class AutomationsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!

  def index
    @tracking_campaign = @client.campaigns.find_by(kind: :shipping_tracking)
    @cashback_campaign = @client.campaigns.find_by(kind: :cashback)
    @cart_recovery_campaign = @client.campaigns.find_by(kind: :cart_recovery)
  end

  def edit_tracking
    @campaign = tracking_campaign
  end

  def update_tracking
    @campaign = tracking_campaign
    if @campaign.update(tracking_params)
      redirect_to automations_path, notice: 'Automação de rastreio salva com sucesso.'
    else
      render :edit_tracking, status: :unprocessable_entity
    end
  end

  def edit_cashback
    @campaign = cashback_campaign
  end

  def update_cashback
    @campaign = cashback_campaign
    if @campaign.update(cashback_params)
      redirect_to automations_path, notice: 'Automação de cashback salva com sucesso.'
    else
      render :edit_cashback, status: :unprocessable_entity
    end
  end

  def edit_cart_recovery
    @campaign = cart_recovery_campaign
    load_cart_recovery_metrics
    load_conversation_connections
  end

  # Define os números responsáveis da automação; só aceita números do próprio cliente.
  def update_numbers
    kind = params[:kind]
    campaign = case kind
               when 'tracking' then tracking_campaign
               when 'cashback' then cashback_campaign
               else cart_recovery_campaign
               end
    back = { 'tracking' => edit_tracking_automation_path, 'cashback' => edit_cashback_automation_path }
           .fetch(kind, edit_cart_recovery_automation_path)

    return redirect_to back, alert: 'Salve a automação antes de importar números.' unless campaign.persisted?
    return redirect_to back, alert: 'Este cliente não usa números Evolution.' unless @client.whatsapp_evolution?

    ids = @client.whatsapp_connections.where(id: Array(params[:connection_ids])).pluck(:id)
    Whatsapp::CampaignConnection.transaction do
      campaign.whatsapp_campaign_connections.where.not(connection_id: ids).destroy_all
      ids.each { |id| campaign.whatsapp_campaign_connections.find_or_create_by!(connection_id: id) }
    end
    redirect_to back, notice: 'Números responsáveis atualizados.'
  end

  def update_cart_recovery
    @campaign = cart_recovery_campaign
    if @campaign.update(cart_recovery_params)
      redirect_to automations_path, notice: 'Automação de recuperação de carrinho salva com sucesso.'
    else
      load_cart_recovery_metrics
      render :edit_cart_recovery, status: :unprocessable_entity
    end
  end

  # Fila de checkouts abandonados com telefone — não usa CampaignAction (não
  # há Order nem sempre Customer pra vincular), então tem sua própria tela.
  def cart_recovery_data
    load_cart_recovery_metrics
    @checkouts = @client.abandoned_checkouts
                        .with_phone
                        .recent
                        .paginate(page: params[:page], per_page: 20)
  end

  def resend_cart_recovery
    checkout = @client.abandoned_checkouts.friendly.find(params[:id])
    campaign = @client.campaigns.find_by(kind: :cart_recovery)
    slot = params[:slot] == 'second' ? 'second' : 'first'
    template = slot == 'second' ? campaign&.resend_message : campaign&.message

    if template.blank?
      return redirect_to cart_recovery_data_automation_path, alert: 'Configure a mensagem antes de reenviar.'
    end

    if SendCartRecoveryNotificationJob.channel_locked?(checkout, slot) &&
       !SendCartRecoveryNotificationJob.channel_available?(checkout, @client, campaign)
      return redirect_to cart_recovery_data_automation_path, alert: 'Canal da 1ª mensagem indisponível.'
    end

    coupon = slot == 'second' ? checkout.second_coupon_code : checkout.first_coupon_code
    SendCartRecoveryNotificationJob.perform_later(checkout.id, template, coupon, slot, true)

    redirect_to cart_recovery_data_automation_path, notice: 'Reenvio agendado com sucesso.'
  rescue ActiveRecord::RecordNotFound
    redirect_to cart_recovery_data_automation_path, alert: 'Checkout não encontrado.'
  end

  private

  # Período dos cards de ticket médio: 7, 30 (padrão) ou 90 dias.
  def load_cart_recovery_metrics
    @period = %w[7 30 90].include?(params[:period].to_s) ? params[:period].to_i : 30
    @metrics = Sales::AbandonedCheckoutMetrics.new(@client, from: @period.days.ago, to: Time.current).call
  end

  # Números da automação que o usuário pode ver, para a caixa de conversas na própria página.
  def load_conversation_connections
    return unless @campaign.persisted? && @campaign.whatsapp_connections.exists?

    @conversation_connections = Whatsapp::Connection.visible_to(current_user, client: @client)
                                                    .where(id: @campaign.whatsapp_connections.select(:id))
                                                    .order(:name).to_a
  end

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  # Só existe uma automação de rastreio por cliente — carrega a existente ou
  # prepara uma nova com valores padrão, sem persistir ainda.
  def tracking_campaign
    @client.campaigns.find_or_initialize_by(kind: :shipping_tracking) do |c|
      c.name = 'Notificação de Rastreio'
      c.start_date = Date.current
      c.end_date = Date.current + 1.year
      c.max_sends = 3
      c.interval_days = 4
    end
  end

  def tracking_params
    params.require(:campaign)
          .permit(:name, :message, :start_date, :end_date, :active, :max_sends, :interval_days)
          .merge(kind: :shipping_tracking)
  end

  # Idem, mas pra automação de cashback.
  def cashback_campaign
    @client.campaigns.find_or_initialize_by(kind: :cashback) do |c|
      c.name = 'Cashback'
      c.start_date = Date.current
      c.end_date = Date.current + 1.year
      c.days_after_purchase = 7
    end
  end

  def cashback_params
    params.require(:campaign)
          .permit(:name, :message, :start_date, :end_date, :active, :days_after_purchase)
          .merge(kind: :cashback)
  end

  # Idem, mas pra automação de recuperação de carrinho.
  def cart_recovery_campaign
    @client.campaigns.find_or_initialize_by(kind: :cart_recovery) do |c|
      c.name = 'Recuperação de Carrinho'
      c.start_date = Date.current
      c.end_date = Date.current + 1.year
      c.send_delay_minutes = 60
      c.resend_delay_hours = 24
    end
  end

  def cart_recovery_params
    params.require(:campaign)
          .permit(
            :name, :message, :start_date, :end_date, :active, :send_delay_minutes,
            :include_coupon, :coupon_code, :resend_enabled, :resend_delay_hours,
            :resend_message, :resend_include_coupon, :resend_coupon_code, :test_phone
          )
          .merge(kind: :cart_recovery)
  end
end
