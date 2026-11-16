class ApplicationController < ActionController::Base
  include Common

  protect_from_forgery with: :exception

  before_action :set_locale
  before_action :authenticate_user!
  before_action :redirect_affiliate_to_events!

  layout 'layouts/application'

  private

  # Depois do login volta pra página que o usuário tentou abrir, ou pro
  # Resumo do site (/crm).
  def after_sign_in_path_for(resource)
    stored = stored_location_for(resource)
    return crm_path if stored.blank?

    stored
  rescue URI::InvalidURIError
    crm_path
  end

  # Lê o idioma de ?locale=, memoriza na sessão pra persistir entre páginas,
  # e cai pro default se não vier nada ou vier um valor inválido.
  def set_locale
    requested = params[:locale].presence
    session[:locale] = requested if requested && I18n.available_locales.map(&:to_s).include?(requested)
    I18n.locale = session[:locale] || I18n.default_locale
  end

  def require_admin!
    unless current_user&.admin?
      redirect_to crm_path, alert: 'Acesso restrito a administradores.'
    end
  end

  # Afiliados (profile_id == 3) só podem acessar events e generate_link
  def redirect_affiliate_to_events!
    return unless user_signed_in?

    return unless current_user.profile_id == Profile::AFFILIATE

    # NÃO roda para Devise (login, logout, etc)
    return if devise_controller?

    # Permite events; a home (logado) agora mostra prévia de vendas da loja,
    # que não é relevante para afiliados
    return if controller_name == 'events'

    redirect_to events_path(utm_code: current_user.utm_code)
  end
end
