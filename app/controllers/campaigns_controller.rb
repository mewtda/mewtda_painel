class CampaignsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_campaign, only: %i[edit update destroy preview send_test send_test_whatsapp schedule cancel details
                                        recipients add_message remove_message]
  before_action :require_draft!, only: %i[edit update schedule add_message remove_message]

  rate_limit to: 5, within: 1.minute, only: %i[send_test send_test_whatsapp],
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
    load_editor_options
  end

  # Linha nova de mensagem (rascunho) no canal pedido; o editor insere o HTML devolvido.
  def add_message
    channel = params[:channel].presence_in(CampaignMessage::CHANNELS) || 'email'
    message = @campaign.messages.create!(channel:, position: @campaign.messages.count)
    load_editor_options
    render partial: 'message', locals: { message:, number: @campaign.messages_for(channel).size }
  end

  def remove_message
    @campaign.messages.find_by(id: params[:message_id])&.destroy
    render json: summary_json
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

    due = schedule_messages!
    due.each { |message| Campaigns::DispatchJob.perform_later(message.id) }
    redirect_to campaigns_path, notice: 'Campanha confirmada. O envio segue sozinho e você acompanha por aqui.'
  end

  def cancel
    return redirect_to(campaigns_path, alert: 'Só dá para cancelar campanhas agendadas, em envio ou pausadas.') unless @campaign.cancelable?

    @campaign.cancel!
    @campaign.update_columns(finished_at: Time.current)
    redirect_to campaigns_path, notice: 'Campanha cancelada. Quem já recebeu não é afetado e o restante não será enviado.'
  end

  def destroy
    return redirect_to campaigns_path, alert: 'Só dá para excluir rascunhos e campanhas canceladas.' unless deletable?

    @campaign.destroy
    redirect_to campaigns_path, notice: 'Campanha excluída.'
  end

  def preview
    template = selected_message('email')&.email_template
    return render(plain: 'Escolha um e-mail para ver a prévia.', layout: false) unless template

    render body: campaign_message(template, root_url).html, content_type: 'text/html', layout: false
  end

  def send_test
    address = params[:test_email].to_s.strip
    template = selected_message('email')&.email_template
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

  # Teste do WhatsApp: envia o modelo escolhido para o número digitado, com o nome "Maria".
  def send_test_whatsapp
    phone = Whatsapp::Phone.normalize(params[:phone])
    template = @client.whatsapp_templates.find_by(id: params[:whatsapp_template_id])
    error = whatsapp_test_error(phone, template)
    return render(json: { error: }, status: :unprocessable_entity) if error

    Whatsapp::Cloud::Api.new(@client).send_template(
      to: phone, name: template.name, language: template.language, body_params: template.uses_variable? ? ['Maria'] : []
    )
    render json: { message: "Teste enviado para #{phone}. Pode levar alguns segundos para chegar." }
  rescue Whatsapp::Cloud::Api::Error => e
    render json: { error: "A Meta recusou o teste: #{e.message}" }, status: :unprocessable_entity
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

  def load_editor_options
    @email_templates = @client.email_templates.order(:name)
    @whatsapp_templates = @client.whatsapp_templates.approved.order(:label)
    @segments = @client.segments.order(:name)
    @whatsapp_configured = Whatsapp::Cloud::Api.new(@client).configured?
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :email_enabled, :whatsapp_enabled, segment_ids: [],
      messages_attributes: %i[id email_template_id whatsapp_template_id send_now send_on send_time _destroy]
    ).tap do |permitted|
      # Só mensagens desta campanha; o canal nunca muda pelo formulário.
      ids = @campaign.messages.pluck(:id).map(&:to_s)
      attrs = permitted[:messages_attributes]
      attrs&.each_key { |key| attrs.delete(key) unless ids.include?(attrs[key][:id].to_s) }
      if permitted.key?(:segment_ids)
        permitted[:segment_ids] = @client.segments.where(id: permitted[:segment_ids]).pluck(:id) | foreign_segment_ids(permitted)
      end
    end
  end

  # Ids de segmentos de outra loja continuam na lista para a validação recusar a gravação.
  def foreign_segment_ids(permitted)
    ids = Array(permitted[:segment_ids]).compact_blank.map(&:to_i)
    ids - @client.segments.where(id: ids).pluck(:id)
  end

  def audiences
    @audiences ||= CampaignMessage::CHANNELS.index_with do |channel|
      Campaigns::Audience.new(@client, @campaign.segments.to_a, channel:).call
    end
  end

  def schedule_error
    return "Falta: #{@campaign.missing_steps.to_sentence.downcase}." if @campaign.missing_steps.any?

    @campaign.enabled_channels.each do |channel|
      next unless audiences[channel].recipients.zero?

      return "Este público não tem ninguém para receber pelo #{channel == 'email' ? 'e-mail' : 'WhatsApp'}."
    end
    return unless @campaign.email_enabled
    return 'O domínio de envio da loja ainda não foi verificado.' unless @client.ses_domain_verified?
    return unless audiences['email'].not_subscribed.positive? && params[:accept_not_subscribed] != '1'

    'Confirme que você entende que parte do público ainda não aceitou receber promoções.'
  end

  # Agenda cada mensagem ativa no seu horário e cancela as de canais desligados. Devolve as que já venceram.
  def schedule_messages!
    now = Time.current
    email = audiences['email']
    Campaign.transaction do
      @campaign.messages.each do |message|
        if @campaign.channel_enabled?(message.channel)
          message.update!(status: 'scheduled', next_run_at: message.first_send_at(now), note: nil)
        else
          message.update!(status: 'cancelled', next_run_at: nil)
        end
      end
      @campaign.update!(status: 'scheduled', published_at: now, published_by: current_user,
                        acknowledged_not_subscribed: (email.not_subscribed if @campaign.email_enabled && email.not_subscribed.positive?))
      @campaign.refresh_from_messages!
    end
    @campaign.messages.select { |message| message.status == 'scheduled' && message.next_run_at <= now }
  end

  def selected_message(channel)
    list = @campaign.messages.where(channel:)
    (params[:message_id].present? && list.find_by(id: params[:message_id])) || list.where.not("#{channel}_template_id" => nil).first
  end

  def whatsapp_test_error(phone, template)
    return 'Informe um celular válido com DDD.' unless phone
    return 'Escolha um modelo de WhatsApp primeiro.' unless template
    return 'Este modelo ainda não foi aprovado pela Meta.' unless template.approved?

    'A API Oficial do WhatsApp da loja não está configurada.' unless Whatsapp::Cloud::Api.new(@client).configured?
  end

  def test_error(address, template)
    return 'Informe um e-mail válido.' unless address.match?(URI::MailTo::EMAIL_REGEXP)
    return 'Escolha o e-mail da mensagem primeiro.' unless template

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
    missing = @campaign.missing_steps
    {
      saved_at: I18n.l(Time.current, format: '%H:%M'),
      steps: { 'name' => @campaign.name.present?, 'audience' => @campaign.segments.any?, 'messages' => messages_done? },
      missing:,
      timing: @campaign.timing_summary,
      ready: missing.empty? && @campaign.enabled_channels.all? { |channel| audiences[channel].recipients.positive? },
      segments: @campaign.segments.map(&:name),
      channels: { email: email_json(audiences['email']), whatsapp: whatsapp_json(audiences['whatsapp']) },
      messages: @campaign.active_messages.map do |message|
        { id: message.id, channel: message.channel, channel_label: message.channel_label,
          template: message.template_name, when: message.when_label }
      end
    }
  end

  def messages_done?
    channels = @campaign.enabled_channels
    channels.any? && channels.all? { |channel| (list = @campaign.messages_for(channel)).any? && list.all?(&:template) }
  end

  def email_json(audience)
    count = @campaign.email_enabled ? @campaign.messages_for('email').size : 0
    {
      enabled: @campaign.email_enabled, messages: count,
      recipients: audience.recipients, subscribed: audience.subscribed, not_subscribed: audience.not_subscribed,
      suppressed: audience.suppressed, without_email: audience.without_email,
      cost: helpers.campaign_cost_label(audience.cost * [count, 1].max),
      daily_limit: audience.daily_limit, used_today: audience.used_today
    }
  end

  def whatsapp_json(audience)
    {
      enabled: @campaign.whatsapp_enabled, configured: Whatsapp::Cloud::Api.new(@client).configured?,
      messages: @campaign.whatsapp_enabled ? @campaign.messages_for('whatsapp').size : 0,
      recipients: audience.recipients, without_phone: audience.without_phone, total: audience.total,
      daily_limit: audience.daily_limit, used_today: audience.used_today
    }
  end
end
