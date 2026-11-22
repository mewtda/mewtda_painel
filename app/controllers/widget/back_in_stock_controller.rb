module Widget
  class BackInStockController < ApplicationController
    MIN_FILL_TIME_MS = 2000

    skip_before_action :authenticate_user!, :redirect_affiliate_to_events!
    protect_from_forgery with: :null_session

    rate_limit to: 10, within: 1.minute, only: :create_alert, with: -> { head :too_many_requests }

    before_action :set_setting
    before_action :require_allowed_origin!, only: :create_alert

    CONFIG_CACHE_TTL = 5.minutes

    # Cache curto no navegador: o botão aparece mais rápido de uma página de produto para outra.
    # Mudanças nas configurações chegam à loja em até 5 minutos.
    def show_config
      expires_in CONFIG_CACHE_TTL, public: true
      render json: @setting.slice(:button_text, :modal_title, :accent_color, :only_marked_products)
    end

    def create_alert
      return head :no_content if bot?
      return daily_limit_reached! if BackInStockAlert.daily_limit_reached?(@setting.client)
      return render_unknown_product if unknown_product?

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

    # Teto de pedidos novos por dia: um pico de cadastros falsos para aqui e não pesa no resto do painel.
    def daily_limit_reached!
      Rails.logger.warn("[BackInStock] limite diário de pedidos atingido (client #{@setting.client_id})")
      head :too_many_requests
    end

    # A loja não respondeu (nil): aceita, pra não perder o pedido de um cliente de verdade.
    def unknown_product?
      BackInStock::VariantCheck.new(@setting.client).valid?(
        handle: alert_params[:product_handle], product_id: alert_params[:shopify_product_id],
        variant_id: alert_params[:shopify_variant_id]
      ) == false
    end

    def render_unknown_product
      Rails.logger.warn("[BackInStock] produto/variação inexistente: #{alert_params[:product_handle]} " \
                        "(client #{@setting.client_id})")
      render json: { errors: ['Produto não encontrado na loja.'] }, status: :unprocessable_entity
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
