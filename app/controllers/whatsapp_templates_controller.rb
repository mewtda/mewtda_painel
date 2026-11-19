# Comunicação > WhatsApp: modelos de mensagem da API Oficial, enviados para aprovação da Meta.
class WhatsappTemplatesController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!
  before_action :set_template, only: %i[edit update destroy submit duplicate]

  def index
    @api_configured = api.configured?
    sync_pending if @api_configured
    @templates = @client.whatsapp_templates.ordered
  end

  def new
    @template = @client.whatsapp_templates.new
  end

  def create
    @template = @client.whatsapp_templates.new(template_params)
    if @template.save
      redirect_to whatsapp_templates_path, notice: 'Modelo salvo como rascunho. Envie para aprovação quando estiver pronto.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    redirect_to whatsapp_templates_path, alert: not_editable_message unless @template.editable?
  end

  def update
    return redirect_to(whatsapp_templates_path, alert: not_editable_message) unless @template.editable?

    if @template.update(template_params.merge(status: 'draft', rejection_reason: nil))
      redirect_to whatsapp_templates_path, notice: 'Modelo atualizado.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def submit
    unless @template.editable?
      return redirect_to(whatsapp_templates_path, alert: 'Este modelo já foi enviado para a Meta.')
    end

    if @template.submit!
      redirect_to whatsapp_templates_path, notice: 'Modelo enviado para aprovação da Meta. Costuma levar de minutos a algumas horas.'
    else
      redirect_to whatsapp_templates_path, alert: "A Meta recusou o envio: #{@template.errors[:base].to_sentence}"
    end
  end

  def duplicate
    copy = @client.whatsapp_templates.create!(
      @template.slice(:body, :body_example, :footer, :button_text, :button_url, :category, :language)
               .merge(label: "#{@template.label} (cópia)".first(120))
    )
    redirect_to edit_whatsapp_template_path(copy), notice: 'Cópia criada. Ajuste e envie para aprovação.'
  end

  def destroy
    if @template.meta_id.present? && api.configured?
      begin
        api.delete_template(name: @template.name)
      rescue Whatsapp::Cloud::Api::Error => e
        return redirect_to(whatsapp_templates_path, alert: "Não foi possível excluir na Meta: #{e.message}")
      end
    end
    @template.destroy
    redirect_to whatsapp_templates_path, notice: 'Modelo excluído.'
  end

  private

  def api
    @api ||= Whatsapp::Cloud::Api.new(@client)
  end

  def sync_pending
    return unless @client.whatsapp_templates.where(status: 'pending').exists?

    Whatsapp::Cloud::TemplateSync.new(@client).call
  rescue Whatsapp::Cloud::Api::Error => e
    flash.now[:alert] = "Não foi possível atualizar o status na Meta agora: #{e.message}"
  end

  def not_editable_message
    'Modelos enviados para a Meta não podem ser editados. Use "Duplicar" para criar uma nova versão.'
  end

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_template
    @template = @client.whatsapp_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to whatsapp_templates_path, alert: 'Modelo não encontrado.'
  end

  def template_params
    params.require(:whatsapp_template).permit(:label, :body, :body_example, :footer, :button_text, :button_url)
  end
end
