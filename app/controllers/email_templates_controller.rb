class EmailTemplatesController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_email_template, only: %i[edit update destroy]

  helper_method :editor_state

  rate_limit to: 5, within: 1.minute, only: :send_test,
             with: -> { render json: { error: 'Muitos testes seguidos. Aguarde um minuto.' }, status: :too_many_requests }

  PREVIEW_PRODUCT = { title: 'Vestido Linho Off White', variant: 'M' }.freeze
  PREVIEW_VARIABLES = { produto: PREVIEW_PRODUCT[:title], variacao: PREVIEW_PRODUCT[:variant], nome: 'Maria' }.freeze
  UPLOAD_CONTENT_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
  UPLOAD_MAX_SIZE = 5.megabytes
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
    if @email_template.update(email_template_params)
      redirect_to email_templates_path, notice: 'E-mail atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def preview
    template = current_client.email_templates.find_by(id: params[:id]) || current_client.email_templates.new
    template.assign_attributes(email_template_params)
    message = preview_message(template)

    render json: { subject: message.subject, preheader: message.preheader, html: message.html }
  end

  def send_test
    address = params[:test_email].to_s.strip
    return render_test_error('Informe um e-mail válido.') unless address.match?(URI::MailTo::EMAIL_REGEXP)
    return render_test_error('O domínio de envio da loja ainda não foi verificado.') unless current_client.ses_domain_verified?

    template = current_client.email_templates.find_by(id: params[:id]) || current_client.email_templates.new
    template.assign_attributes(email_template_params)
    return render_test_error('O e-mail tem erros: confira o nome, o assunto e os blocos.') unless template.valid?

    message = test_message(template, address)
    sent = Ses::SendEmailService.new(current_client).call(
      to: address, subject: "[TESTE] #{message.subject}", html_body: message.html,
      text_body: message.text, unsubscribe_url: message.unsubscribe_url
    )
    return render json: { message: "Teste enviado para #{address}." } if sent

    render_test_error('Não foi possível enviar: o e-mail está na lista de recusa ou o limite de envios foi atingido.')
  rescue Aws::Errors::ServiceError => e
    Rails.logger.error "[EmailTemplates] Teste para #{address}: #{e.message}"
    render_test_error('A AWS recusou o envio. Tente de novo em instantes.')
  end

  # Upload de imagem dos blocos: devolve o signed_id (guardado no bloco) e uma
  # URL pra miniatura no editor.
  def upload_image
    file = params[:file]
    error = upload_error(file)
    return render(json: { error: }, status: :unprocessable_entity) if error

    blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: file.original_filename,
                                                  content_type: file.content_type)
    render json: { signed_id: blob.signed_id, url: url_for(blob) }
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
      product: PREVIEW_PRODUCT.merge(image: PREVIEW_PRODUCT_IMAGE, url: storefront_or_root_url),
      default_url: storefront_or_root_url,
      logo_url: (url_for(current_client.logo) if current_client.logo.attached?),
      unsubscribe_url: root_url,
      asset_url: ->(blob) { url_for(blob) },
      preview: true
    )
  end

  def test_message(template, address)
    EmailTemplates::Message.new(
      template,
      variables: PREVIEW_VARIABLES.merge(loja: current_client.name),
      product: PREVIEW_PRODUCT.merge(url: storefront_or_root_url),
      default_url: storefront_or_root_url,
      logo_url: public_logo_url,
      unsubscribe_url: EmailSuppression.unsubscribe_url(current_client, address, template: template.persisted? ? template : nil)
    )
  end

  def public_logo_url
    return unless current_client.logo.attached?

    Rails.application.routes.url_helpers.rails_blob_url(current_client.logo, host: BackInStockSetting::WIDGET_HOST)
  end

  def render_test_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def storefront_or_root_url
    url = current_client.storefront_url
    url.match?(%r{\Ahttps?://[^/]+\z}) ? url : root_url
  end

  def upload_error(file)
    return 'Nenhum arquivo enviado.' unless file.respond_to?(:content_type)
    return 'Envie uma imagem PNG, JPG, GIF ou WEBP.' unless UPLOAD_CONTENT_TYPES.include?(file.content_type)

    'A imagem deve ter no máximo 5 MB.' if file.size > UPLOAD_MAX_SIZE
  end

  # Estado inicial do editor: blocos (com URL de miniatura das imagens),
  # estilo global e cor de destaque.
  def editor_state(template)
    {
      blocks: template.content_blocks.map { |block| with_thumbnails(block) },
      design: template.design,
      logo_url: (url_for(current_client.logo) if current_client.logo.attached?),
      store_name: current_client.name
    }
  end

  def with_thumbnails(block)
    block = block.merge('image_url' => thumbnail_url(block['image_id'])) if block.key?('image_id')
    return block unless block['items'].is_a?(Array)

    block.merge('items' => block['items'].map { |item| item.merge('image_url' => thumbnail_url(item['image_id'])) })
  end

  def thumbnail_url(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id) if signed_id.present?
    url_for(blob) if blob
  end

  def preset_attributes
    EmailTemplate.preset(params[:preset]) || EmailTemplate::BLANK
  end

  def email_template_params
    params.require(:email_template).permit(
      :name, :subject, :accent_color, :blocks_json, :design_json
    )
  end
end
