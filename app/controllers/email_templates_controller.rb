class EmailTemplatesController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_email_template, only: %i[edit update destroy]

  PREVIEW_PRODUCT = { title: 'Vestido Linho Off White', variant: 'M' }.freeze
  PREVIEW_VARIABLES = { produto: PREVIEW_PRODUCT[:title], variacao: PREVIEW_PRODUCT[:variant], nome: 'Maria' }.freeze
  PREVIEW_PRODUCT_IMAGE = "data:image/svg+xml;utf8,#{ERB::Util.url_encode(<<~SVG.squish)}".freeze
    <svg xmlns="http://www.w3.org/2000/svg" width="480" height="600" viewBox="0 0 480 600">
      <rect width="480" height="600" fill="#ececef"/>
      <text x="240" y="300" font-family="Arial" font-size="24" fill="#9a9aa5" text-anchor="middle">Foto do produto</text>
    </svg>
  SVG

  def index
    @email_templates = current_client.email_templates.order(created_at: :desc)
  end

  def new
    @email_template = current_client.email_templates.new(preset_attributes)
  end

  def create
    @email_template = current_client.email_templates.new(email_template_params)
    if @email_template.save
      redirect_to email_templates_path, notice: 'E-mail criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @email_template.image.purge if params.dig(:email_template, :remove_image) == '1'
    @email_template.image_bottom.purge if params.dig(:email_template, :remove_image_bottom) == '1'

    if @email_template.update(email_template_params)
      redirect_to email_templates_path, notice: 'E-mail atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def preview
    template = current_client.email_templates.find_by(id: params[:id]) || current_client.email_templates.new
    template.assign_attributes(email_template_params.except(:image, :image_bottom))
    message = preview_message(template)

    render json: { subject: message.subject, html: message.html }
  end

  def destroy
    @email_template.destroy
    redirect_to email_templates_path, notice: 'E-mail excluído com sucesso.'
  end

  private

  def current_client
    @client
  end
  helper_method :current_client

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_email_template
    @email_template = current_client.email_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to email_templates_path, alert: 'E-mail não encontrado.'
  end

  def preview_message(template)
    EmailTemplates::Message.new(
      template,
      variables: PREVIEW_VARIABLES.merge(loja: current_client.name),
      product: (PREVIEW_PRODUCT if template.back_in_stock?),
      image_url: template.back_in_stock? ? PREVIEW_PRODUCT_IMAGE : preview_image(:image, template.image),
      image_bottom_url: preview_image(:image_bottom, template.image_bottom),
      logo_url: (url_for(current_client.logo) if current_client.logo.attached?),
      button_url: root_url,
      unsubscribe_url: root_url
    )
  end

  def preview_image(field, attachment)
    upload = params.dig(:email_template, field)
    return "data:#{upload.content_type};base64,#{Base64.strict_encode64(upload.read)}" if image_upload?(upload)
    return if params.dig(:email_template, :"remove_#{field}") == '1'

    url_for(attachment) if attachment.attached?
  end

  def image_upload?(upload)
    upload.respond_to?(:content_type) && upload.content_type.to_s.start_with?('image/')
  end

  def preset_attributes
    EmailTemplate.preset(params[:preset]) || {}
  end

  def email_template_params
    params.require(:email_template).permit(
      :name, :subject, :heading, :body, :button_text, :button_url, :coupon_code,
      :accent_color, :layout, :trigger_kind, :active, :image, :image_bottom,
      :trigger_delay_hours, :trigger_inactive_days, :trigger_days_after_purchase
    )
  end
end
