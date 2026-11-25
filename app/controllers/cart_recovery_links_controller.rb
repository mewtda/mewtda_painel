# Link do botão da mensagem de recuperação de carrinho (API Oficial): /carrinho/:slug.
# Leva para o checkout abandonado na loja e, se a mensagem levou cupom, passa antes por /discount/CUPOM
# da Shopify, que aplica o cupom e segue para o checkout.
class CartRecoveryLinksController < ApplicationController
  skip_before_action :authenticate_user!, :redirect_affiliate_to_events!

  def show
    checkout = AbandonedCheckout.find_by(slug: params[:slug].to_s)
    target = checkout && self.class.target_url(checkout)
    return redirect_to(target, allow_other_host: true) if target

    redirect_to(checkout&.client&.site_url.presence || root_url, allow_other_host: true)
  end

  def self.target_url(checkout)
    uri = URI.parse(checkout.recovery_url.to_s)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    code = checkout.first_coupon_code.presence
    return uri.to_s unless code

    "#{uri.scheme}://#{uri.host}/discount/#{ERB::Util.url_encode(code)}?redirect=#{CGI.escape(uri.request_uri)}"
  rescue URI::InvalidURIError
    nil
  end
end
