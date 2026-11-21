# Comunicação > WhatsApp: modelos de mensagem da conta do WhatsApp conectada (API Oficial).
# Os modelos são criados no Gerenciador do WhatsApp da Meta; aqui o painel só importa e mostra
# status e números da Meta (enviadas, entregues, lidas, cliques).
class WhatsappTemplatesController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!

  SYNC_EVERY = 10.minutes

  def index
    @api_configured = api.configured?
    sync_from_meta if @api_configured && sync_due?
    flash.now[:alert] = @sync_error if @sync_error
    @stats_error ||= flash[:stats_error]
    @templates = @client.whatsapp_templates.where.not(status: 'draft').ordered
    @stats_synced_at = @templates.filter_map(&:stats_synced_at).max
  end

  # Botão "Atualizar da Meta": importa os modelos da conta conectada, status e números.
  def sync
    return redirect_to(whatsapp_templates_path, alert: 'A API Oficial do WhatsApp não está configurada.') unless api.configured?

    result = sync_from_meta
    return redirect_to(whatsapp_templates_path, alert: @sync_error) unless result

    flash[:stats_error] = result.stats_error if result.stats_error
    redirect_to whatsapp_templates_path, notice: sync_notice(result)
  end

  # Liga os insights de modelos na conta do WhatsApp (sem isso a Meta não informa enviadas/lidas por modelo).
  def enable_insights
    api.enable_template_insights!
    sync_from_meta
    redirect_to whatsapp_templates_path,
                notice: 'Insights de modelos ativados na Meta. Os números aparecem conforme a Meta for processando.'
  rescue Whatsapp::Cloud::Api::Error => e
    redirect_to whatsapp_templates_path, alert: "A Meta recusou: #{e.message}"
  end

  private

  def api
    @api ||= Whatsapp::Cloud::Api.new(@client)
  end

  def sync_due?
    last = @client.whatsapp_templates.maximum(:synced_at)
    last.nil? || last < SYNC_EVERY.ago || @client.whatsapp_templates.where(status: 'pending').exists?
  end

  def sync_from_meta
    result = Whatsapp::Cloud::TemplateSync.new(@client).call
    @stats_error = result.stats_error
    result
  rescue Whatsapp::Cloud::Api::Error => e
    @sync_error = "Não foi possível atualizar da Meta agora: #{e.message}"
    nil
  end

  def sync_notice(result)
    return 'Modelos atualizados da Meta.' if result.imported.zero?

    "Modelos atualizados da Meta. #{result.imported} #{result.imported == 1 ? 'modelo novo importado' : 'modelos novos importados'}."
  end

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end
end
