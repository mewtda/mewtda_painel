module Widget
  class BackInStockUnsubscribesController < ApplicationController
    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!

    layout 'public_notice'

    before_action :set_alert

    def show; end

    def create
      @alert.unsubscribe!
      render :done
    end

    private

    def set_alert
      @alert = BackInStockAlert.includes(:client).find_by_token_for(:unsubscribe, params[:token])
      render :invalid, status: :not_found unless @alert
    end
  end
end
