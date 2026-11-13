module Widget
  class BackInStockController < ApplicationController
    MIN_FILL_TIME_MS = 2000

    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!
    protect_from_forgery with: :null_session

    rate_limit to: 10, within: 1.minute, only: :create_alert, with: -> { head :too_many_requests }

    before_action :set_setting
    before_action :require_allowed_origin!, only: :create_alert

    def show_config
      render json: @setting.slice(:button_text, :modal_title, :accent_color, :only_marked_products)
    end

    def create_alert
      return head :no_content if bot?

      alert = @setting.client.back_in_stock_alerts.register(alert_params)

      if alert.persisted?
        head :created
      else
        render json: { errors: alert.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_setting
      @setting = BackInStockSetting.active.find_by(public_token: params[:token])
      head :not_found unless @setting
    end

    def require_allowed_origin!
      return if @setting.allowed_origin?(request.origin)

      Rails.logger.warn("[BackInStock] origin bloqueada: #{request.origin} (client #{@setting.client_id})")
      head :forbidden
    end

    def bot?
      params[:website].present? || params[:elapsed_ms].to_i < MIN_FILL_TIME_MS
    end

    def alert_params
      params.require(:alert).permit(
        :shopify_product_id, :shopify_variant_id, :shopify_customer_id, :product_handle,
        :product_title, :variant_title, :sku, :price, :image_url, :email, :phone
      )
    end
  end
end
