module BackInStock
  # Roda a cada 10 minutos: confere na loja se as variações com pedido de aviso voltaram e manda o e-mail.
  # Protegido contra volume anormal: uma rodada por vez, tempo máximo por rodada, número máximo de
  # produtos por loja em cada rodada (os menos conferidos primeiro, em rodízio) e consulta com tempo curto.
  class RestockCheckJob < ApplicationJob
    DEFAULT_VARIANT_TITLE = 'Default Title'.freeze
    LOCK_KEY = 7_204_311_001
    MAX_RUN_TIME = 8.minutes
    MAX_HANDLES_PER_CLIENT = 150
    FETCH_TIMEOUT = 5

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
      fetcher = Shopify::FetchProductService.new(setting.client, timeout: FETCH_TIMEOUT)
      pending = setting.client.back_in_stock_alerts.pending

      handles_to_check(pending).each do |handle|
        break if out_of_time?

        alerts = pending.where(product_handle: handle)
        result = fetcher.lookup(handle)
        if result.found?
          process(alerts, result.product)
        elsif result.missing?
          handle_missing(setting.client, alerts, handle)
        end
        alerts.update_all(checked_at: Time.current)
      end
    end

    # Rodízio: os produtos conferidos há mais tempo (ou nunca) primeiro.
    def handles_to_check(pending)
      pending.group(:product_handle)
             .order(Arel.sql("MIN(COALESCE(checked_at, 'epoch'::timestamp))"), :product_handle)
             .limit(MAX_HANDLES_PER_CLIENT)
             .pluck(:product_handle)
    end

    def process(alerts, product)
      variants = product['variants'].index_by { |variant| variant['id'] }
      return if variants.empty?

      cancel(alerts.where.not(shopify_variant_id: variants.keys))
      alerts.where(shopify_variant_id: variants.keys).order(:created_at).pluck(:id, :shopify_variant_id)
            .each { |id, variant_id| notify(id, product, variants[variant_id]) }
    end

    # A página do produto deu 404. Pode ser produto apagado, rascunho/despublicado ou link trocado:
    # pergunta à Shopify pelo id. Apagado → cancela; link novo → atualiza; rascunho → continua esperando.
    def handle_missing(client, alerts, handle)
      ids = alerts.distinct.pluck(:shopify_product_id)
      products = admin_products(client, ids)
      return unless products

      ids.each do |id|
        scope = alerts.where(shopify_product_id: id)
        node = products[id]
        if node.nil?
          cancel(scope)
        elsif node['handle'].present? && node['handle'] != handle
          scope.update_all(product_handle: node['handle'], updated_at: Time.current)
        end
      end
    end

    def admin_products(client, ids)
      gids = ids.map { |id| "gid://shopify/Product/#{id}" }
      data = Shopify::Client.new(client).query("{ nodes(ids: #{gids.to_json}) { ... on Product { handle } } }")
      ids.zip(Array(data['nodes'])).to_h
    rescue StandardError => e
      Rails.logger.warn "[BackInStock::RestockCheck] Shopify Admin indisponível (client #{client.id}): #{e.message}"
      nil
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
