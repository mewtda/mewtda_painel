class EmailConfigurationsController < ApplicationController
  include ClientScoped

  before_action :set_client
  before_action :require_client!

  REFRESH_NOTICES = {
    'verified' => 'Domínio verificado com sucesso!',
    'pending' => 'Ainda não verificado — confira os registros de DNS.',
    'failed' => 'A AWS não encontrou os registros de DNS. Confira se foram cadastrados exatamente como abaixo.'
  }.freeze

  def edit; end

  def update
    current_client.assign_attributes(domain_params)
    return render(:edit, status: :unprocessable_entity) unless current_client.valid?

    configure_domain if current_client.email_sending_domain_changed?
    redirect_to edit_email_configuration_path, notice: update_notice
  rescue Aws::Errors::ServiceError => e
    redirect_to edit_email_configuration_path, alert: "Erro ao configurar o domínio na AWS: #{e.message}"
  end

  def refresh_status
    status = identity_service.refresh_status!
    redirect_to edit_email_configuration_path, notice: REFRESH_NOTICES.fetch(status)
  rescue Aws::Errors::ServiceError => e
    redirect_to edit_email_configuration_path, alert: "Erro ao verificar o domínio: #{e.message}"
  end

  private

  def current_client
    @client
  end
  helper_method :current_client

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def configure_domain
    domain = current_client.email_sending_domain
    domain.present? ? identity_service.register!(domain) : current_client.clear_email_sending!
  end

  def update_notice
    return 'Configuração salva.' unless current_client.ses_verification_status == 'pending'

    'Domínio salvo. Cadastre os registros de DNS abaixo pra concluir a verificação.'
  end

  def identity_service
    Ses::DomainIdentityService.new(current_client)
  end

  def domain_params
    params.require(:client).permit(:email_sending_domain)
  end
end
