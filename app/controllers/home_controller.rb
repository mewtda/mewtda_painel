class HomeController < ApplicationController
  skip_before_action :authenticate_user!, only: [:index, :sites, :app_page, :crm_page, :privacy]

  # Logado, a raiz sempre leva ao painel (/crm); deslogado, mostra a landing.
  def index
    return redirect_to(crm_path) if user_signed_in?

    render 'home/city', layout: 'home_city'
  end

  # Página pública do produto "Sua Loja" (criação de sites Shopify)
  def sites; end

  # Página pública do produto "App" (app iOS/Android da loja — em breve)
  def app_page; end

  # Página pública do produto "MeuCRM"
  def crm_page; end

  # Política de privacidade pública dos apps — página autocontida, sem layout
  def privacy
    render layout: false
  end
end
