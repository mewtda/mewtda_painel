module BackInStock
  class RestockCheckJob < ApplicationJob
    DEFAULT_VARIANT_TITLE = 'Default Title'.freeze

    queue_as :default

    def perform
      BackInStockSetting.active.includes(:client).find_each do |setting|
        check(setting) if ready?(setting)
      rescue StandardError => e
        Rails.logger.error "[BackInStock::RestockCheck] Erro no client #{setting.client_id}: #{e.message}"
      end
    end

    private

    def ready?(setting)
      setting.client.tools_email_domain.present? && setting.email_template.present?
    end

    def check(setting)
      fetcher = Shopify::FetchProductService.new(setting.client)
      pending = setting.client.back_in_stock_alerts.pending

      pending.distinct.pluck(:product_handle).each do |handle|
        product = fetcher.call(handle)
        process(pending.where(product_handle: handle), product) if product
      end
    end

    def process(alerts, product)
      variants = product['variants'].index_by { |variant| variant['id'] }
      return if variants.empty?

      cancel_missing(alerts, variants.keys)
      alerts.where(shopify_variant_id: variants.keys).order(:created_at).pluck(:id, :shopify_variant_id)
            .each { |id, variant_id| notify(id, product, variants[variant_id]) }
    end

    def cancel_missing(alerts, ids)
      now = Time.current
      alerts.where.not(shopify_variant_id: ids).update_all(status: 'cancelled', cancelled_at: now, updated_at: now)
    end

    def notify(alert_id, product, variant)
      NotifyJob.perform_now(alert_id, snapshot(product, variant)) if variant['available']
    end

    def snapshot(product, variant)
      {
        'title' => product['title'],
        'variant' => (variant['title'] unless variant['title'] == DEFAULT_VARIANT_TITLE),
        'image' => image_url(variant.dig('featured_image', 'src') || product['featured_image'])
      }
    end

    def image_url(source)
      url = source.to_s.start_with?('//') ? "https:#{source}" : source.to_s
      url if url.start_with?('https://')
    end
  end
end
