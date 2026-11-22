module BackInStock
  # Roda a cada 10 minutos: confere na Shopify (Admin API, em lotes) se as variações com pedido de aviso
  # voltaram e manda o e-mail. Protegido contra volume anormal: uma rodada por vez, tempo máximo por rodada
  # e número máximo de produtos por loja em cada rodada (os menos conferidos primeiro, em rodízio).
  class RestockCheckJob < ApplicationJob
    DEFAULT_VARIANT_TITLE = 'Default Title'.freeze
    LOCK_KEY = 7_204_311_001
    MAX_RUN_TIME = 8.minutes
    MAX_PRODUCTS_PER_CLIENT = 150

    queue_as :default

    def perform
      with_run_lock do
        @deadline = monotonic_now + MAX_RUN_TIME
        BackInStockSetting.active.includes(:client).find_each do |setting|
          break if out_of_time?

          check(setting) if ready?(setting)
        rescue StandardError => e
          Rails.logger.error "[BackInStock::RestockCheck] Erro no client #{setting.client_id}: #{e.message}"
        end
      end
    end

    private

    # Se a rodada anterior ainda não terminou, esta não começa (evita rodadas empilhadas no worker).
    def with_run_lock
      connection = ActiveRecord::Base.connection
      unless connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")
        return Rails.logger.warn('[BackInStock::RestockCheck] rodada anterior ainda em andamento; pulando')
      end

      begin
        yield
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{LOCK_KEY})")
      end
    end

    def ready?(setting)
      setting.client.tools_email_domain.present? && setting.email_template.present?
    end

    def check(setting)
      pending = setting.client.back_in_stock_alerts.pending
      ids = product_ids_to_check(pending)
      return if ids.empty?

      products = Shopify::ProductsByIds.new(setting.client).call(ids)
      ids.each do |id|
        next unless products.key?(id)

        alerts = pending.where(shopify_product_id: id)
        update_product(alerts, products[id])
        alerts.update_all(checked_at: Time.current)
      end
    end

    # Rodízio: os produtos conferidos há mais tempo (ou nunca) primeiro.
    def product_ids_to_check(pending)
      pending.group(:shopify_product_id)
             .order(Arel.sql("MIN(COALESCE(checked_at, 'epoch'::timestamp))"), :shopify_product_id)
             .limit(MAX_PRODUCTS_PER_CLIENT)
             .pluck(:shopify_product_id)
    end

    # Apagado na Shopify → cancela. Link trocado → atualiza. Rascunho/fora da loja → continua esperando.
    def update_product(alerts, product)
      return cancel(alerts) if product.nil?

      alerts.where.not(product_handle: product['handle'])
            .update_all(product_handle: product['handle'], updated_at: Time.current)
      process(alerts, product) if product['live']
    end

    def process(alerts, product)
      variants = product['variants'].index_by { |variant| variant['id'] }
      return if variants.empty?

      cancel(alerts.where.not(shopify_variant_id: variants.keys))
      alerts.where(shopify_variant_id: variants.keys).order(:created_at).pluck(:id, :shopify_variant_id)
            .each { |id, variant_id| notify(id, product, variants[variant_id]) }
    end

    def cancel(alerts)
      now = Time.current
      alerts.update_all(status: 'cancelled', cancelled_at: now, updated_at: now)
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

    def out_of_time? = monotonic_now > @deadline

    def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
