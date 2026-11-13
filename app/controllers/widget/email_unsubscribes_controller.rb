module Widget
  # Link "Não quero mais receber estes e-mails" do rodapé. Coloca o e-mail na
  # lista de recusa da loja (EmailSuppression) — nenhum envio sai mais pra ele.
  # O POST também atende o one-click do Gmail/Outlook (List-Unsubscribe-Post),
  # que chega sem token CSRF; o token assinado na URL já autentica o pedido.
  class EmailUnsubscribesController < ApplicationController
    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!
    skip_forgery_protection only: :create

    layout 'public_notice'

    before_action :set_recipient

    def show
      @already_unsubscribed = EmailSuppression.suppressed?(@client, @email)
    end

    def create
      EmailSuppression.unsubscribe!(@client, @email)
      render :done
    end

    private

    def set_recipient
      @client, @email = EmailSuppression.resolve_token(params[:token])
      render 'widget/back_in_stock_unsubscribes/invalid', status: :not_found unless @client
    end
  end
end
