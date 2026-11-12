class BackInStockSetting < ApplicationRecord
  WIDGET_HOST = 'https://www.mewtda.com.br'.freeze

  belongs_to :client

  has_secure_token :public_token

  scope :active, -> { where(active: true) }

  validates :button_text, :modal_title, presence: true, length: { maximum: 80 }
  validates :accent_color, format: { with: /\A#[0-9a-fA-F]{6}\z/ }

  def script_url
    "#{WIDGET_HOST}/widget/back_in_stock.js"
  end

  def email_template
    client.email_templates.back_in_stock.where(active: true).order(updated_at: :desc).first
  end

  def allowed_hosts
    [client.site_url, client.shopify_shop_url].compact_blank.map { |url| host_of(url) }.uniq
  end

  def allowed_origin?(origin)
    origin.present? && allowed_hosts.include?(host_of(origin))
  end

  private

  def host_of(url)
    URI.parse(url.match?(%r{\Ahttps?://}) ? url : "https://#{url}").host.to_s.delete_prefix('www.')
  rescue URI::InvalidURIError
    ''
  end
end
