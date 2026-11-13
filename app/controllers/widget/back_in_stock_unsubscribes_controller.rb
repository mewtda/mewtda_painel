module Widget
  # Links de descadastro enviados antes da lista de recusa existir. Hoje o
  # rodapé usa EmailUnsubscribesController; aqui o efeito é o mesmo: o e-mail
  # entra na lista de recusa e todos os avisos pendentes dele são cancelados.
  class BackInStockUnsubscribesController < ApplicationController
    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!

    layout 'public_notice'

    before_action :set_alert

    def show; end

    def create
      EmailSuppression.unsubscribe!(@alert.client, @alert.email)
      render :done
    end

    private

    def set_alert
      @alert = BackInStockAlert.includes(:client).find_by_token_for(:unsubscribe, params[:token])
      render :invalid, status: :not_found unless @alert
    end
  end
end
