class CampaignsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_campaign, only: %i[edit update destroy preview send_test schedule cancel details recipients]
  before_action :require_draft!, only: %i[edit update schedule]

  rate_limit to: 5, within: 1.minute, only: :send_test,
             with: -> { render json: { error: 'Muitos testes seguidos. Aguarde um minuto.' }, status: :too_many_requests }

  def index
    @campaigns = @client.campaigns.includes(:segment, :email_template).order(updated_at: :desc)
    @campaigns = @campaigns.where(channel: params[:canal]) if params[:canal].in?(Campaign::CHANNELS.keys)
    @campaigns = @campaigns.where('name ILIKE ?', "%#{Campaign.sanitize_sql_like(params[:q].to_s.strip)}%") if params[:q].present?
  end

  def details
    render partial: 'details', locals: { campaign: @campaign, pending: @campaign.recipients.where(status: 'pending').count }
  end

  def recipients
    status = params[:status].presence_in(Spreadsheets::CampaignRecipients::STATUSES)
    return redirect_to(campaigns_path, alert: 'Lista não encontrada.') unless status

    sheet = Spreadsheets::CampaignRecipients.new(@campaign, status)
    send_data sheet.to_xlsx, filename: sheet.filename, type: sheet.content_type
  end

  def create
    campaign = @client.campaigns.create!(created_by: current_user)
    redirect_to edit_campaign_path(campaign)
  end

  def edit
    @email_templates = @client.email_templates.order(:name)
    @segments = @client.segments.order(:name)
  end

  def update
    if @campaign.update(campaign_params)
      render json: summary_json
    else
      render json: { error: @campaign.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def schedule
    error = schedule_error
    return redirect_to(edit_campaign_path(@campaign), alert: error) if error

    audience = @campaign.audience
    @campaign.update!(status: 'scheduled', next_run_at: @campaign.first_send_at, published_at: Time.current,
                      published_by: current_user,
                      acknowledged_not_subscribed: (audience.not_subscribed if audience.not_subscribed.positive?))
    Campaigns::DispatchJob.perform_later(@campaign.id)
    redirect_to campaigns_path, notice: 'Campanha confirmada. O envio segue sozinho e você acompanha por aqui.'
  end

  def cancel
    return redirect_to(campaigns_path, alert: 'Só dá para cancelar campanhas agendadas, em envio ou pausadas.') unless @campaign.cancelable?

    @campaign.update!(status: 'cancelled', next_run_at: nil, finished_at: Time.current)
    redirect_to campaigns_path, notice: 'Campanha cancelada. Quem já recebeu não é afetado e o restante não será enviado.'
  end

  def destroy
    return redirect_to campaigns_path, alert: 'Só dá para excluir rascunhos e campanhas canceladas.' unless deletable?

    @campaign.destroy
    redirect_to campaigns_path, notice: 'Campanha excluída.'
  end

  def preview
    return render(plain: 'Escolha um e-mail para ver a prévia.', layout: false) unless @campaign.email_template

    render body: campaign_message(@campaign.email_template, root_url).html, content_type: 'text/html', layout: false
  end

  def send_test
    address = params[:test_email].to_s.strip
    template = @campaign.email_template
    error = test_error(address, template)
    return render(json: { error: }, status: :unprocessable_entity) if error

    message = campaign_message(template, EmailSuppression.unsubscribe_url(@client, address, template:))
    sent = Ses::SendEmailService.new(@client).call(
      to: address, subject: "[TESTE] #{message.subject}", html_body: message.html,
      text_body: message.text, unsubscribe_url: message.unsubscribe_url
    )
    return render json: { message: "Teste enviado para #{address}." } if sent

    render json: { error: 'Não foi possível enviar: o e-mail está na lista de recusa ou o limite de envios foi atingido.' },
           status: :unprocessable_entity
  rescue Aws::Errors::ServiceError => e
    Rails.logger.error "[Campaigns] Teste para #{address}: #{e.message}"
    render json: { error: 'A AWS recusou o envio. Tente de novo em instantes.' }, status: :unprocessable_entity
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_campaign
    @campaign = @client.campaigns.find_by(id: params[:id])
    redirect_to campaigns_path, alert: 'Campanha não encontrada.' unless @campaign
  end

  def require_draft!
    return if @campaign.draft?

    respond_to do |format|
      format.json { render json: { error: 'Esta campanha não pode mais ser editada.' }, status: :unprocessable_entity }
      format.html { redirect_to campaigns_path, alert: 'Esta campanha não pode mais ser editada.' }
    end
  end

  def deletable? = @campaign.status.in?(%w[draft cancelled])

  def campaign_params
    params.require(:campaign).permit(:name, :email_template_id, :segment_id, :send_mode, :scheduled_on,
                                     :scheduled_time, :window_from, :window_to, window_days: [])
  end

  def schedule_error
    return "Falta: #{@campaign.missing_steps.to_sentence.downcase}." if @campaign.missing_steps.any?

    audience = @campaign.audience
    return 'Este público não tem ninguém para receber.' if audience.recipients.zero?
    return 'O domínio de envio da loja ainda não foi verificado.' unless @client.ses_domain_verified?
    return unless audience.not_subscribed.positive? && params[:accept_not_subscribed] != '1'

    'Confirme que você entende que parte do público ainda não aceitou receber promoções.'
  end

  def test_error(address, template)
    return 'Informe um e-mail válido.' unless address.match?(URI::MailTo::EMAIL_REGEXP)
    return 'Escolha o e-mail da campanha primeiro.' unless template

    'O domínio de envio da loja ainda não foi verificado.' unless @client.ses_domain_verified?
  end

  def campaign_message(template, unsubscribe_url)
    EmailTemplates::Message.new(
      template, variables: { nome: 'Maria', loja: @client.name }, default_url: storefront_or_root_url,
                logo_url: logo_url, unsubscribe_url:, asset_url: ->(blob) { url_for(blob) }
    )
  end

  def logo_url = (url_for(@client.logo) if @client.logo.attached?)

  def storefront_or_root_url
    url = @client.storefront_url
    url.match?(%r{\Ahttps?://[^/]+\z}) ? url : root_url
  end

  def summary_json
    audience = @campaign.audience
    {
      saved_at: I18n.l(Time.current, format: '%H:%M'),
      steps: @campaign.step_done,
      missing: @campaign.missing_steps,
      timing: @campaign.timing_summary,
      ready: @campaign.missing_steps.empty? && audience.recipients.positive?,
      send_mode: @campaign.send_mode,
      template_id: @campaign.email_template_id,
      template_subject: @campaign.email_template&.subject,
      audience: audience_json(audience)
    }
  end

  def audience_json(audience)
    capacity = first_day_capacity(audience)
    {
      recipients: audience.recipients, subscribed: audience.subscribed, not_subscribed: audience.not_subscribed,
      suppressed: audience.suppressed, without_email: audience.without_email,
      cost: helpers.campaign_cost_label(audience.cost),
      daily_limit: audience.daily_limit, used_today: audience.used_today, first_day_capacity: capacity,
      first_day_label: @campaign.first_day_label, resume_label: @campaign.resume_label,
      timing_ready: @campaign.step_done['timing'],
      resume_time: format('%<hour>02d:00', hour: Campaign::RESUME_HOUR),
      days_needed: days_needed(audience, capacity)
    }
  end

  # Quantos e-mails cabem no primeiro dia de envio: o que sobrou de hoje, ou o
  # limite cheio quando o primeiro envio é em outro dia.
  def first_day_capacity(audience)
    return unless audience.daily_limit

    first_day = @campaign.first_send_at.in_time_zone.to_date
    first_day == Time.zone.today ? [audience.daily_limit - audience.used_today, 0].max : audience.daily_limit
  end

  def days_needed(audience, capacity)
    return 1 unless capacity && audience.recipients > capacity

    1 + ((audience.recipients - capacity).to_f / audience.daily_limit).ceil
  end
end
