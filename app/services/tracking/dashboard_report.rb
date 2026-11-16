module Tracking
  # Relatório da tela "Trackeamento site" (eventos do pixel da Shopify). As
  # consultas são pesadas, então roda no TrackingReportJob, fora da requisição
  # web; o resultado vira as variáveis do partial dashboard/_report.
  class DashboardReport
    def initialize(client:, period:, year: nil, month: nil)
      @client = client
      @period = period.presence || "1"
      @filter_year = year.presence&.to_i
      @filter_month = month.presence&.to_i
    end

    # Variáveis de instância que o partial usa (@counts, @sessions...).
    def assigns
      compute
      instance_values.except("filter_year", "filter_month").symbolize_keys
    end

    private

    def compute
      # Filtro por mês/ano tem prioridade sobre os filtros rápidos
      if @filter_year.present? && @filter_month.present?
        start_date = Time.zone.local(@filter_year, @filter_month, 1).beginning_of_day
        end_date   = start_date.end_of_month
        range      = start_date..end_date
        # Período anterior = mês anterior completo
        prev_start = (start_date - 1.month).beginning_of_month
        prev_end   = prev_start.end_of_month
        prev_range = prev_start..prev_end
        # Marca que está usando filtro mensal
        @using_month_filter = true
      else
        range = case @period
                when "7"  then 7.days.ago..Time.current
                when "15" then 15.days.ago..Time.current
                when "30" then 30.days.ago..Time.current
                else Time.current.beginning_of_day..Time.current
                end

        days_count = { "7" => 7, "15" => 15, "30" => 30 }[@period] || 1
        prev_range = (range.first - days_count.days)..(range.first - 1.second)
      end

      base_scope = ShopifyEvent.where(client_id: @client.id, created_at: range)
      prev_scope = ShopifyEvent.where(client_id: @client.id, created_at: prev_range)

      funnel_kinds = %w[page_viewed product_viewed product_added_to_cart checkout_started checkout_completed]

      counts_query      = base_scope.where(kind: funnel_kinds).group(:kind).count
      prev_counts_query = prev_scope.where(kind: funnel_kinds).group(:kind).count

      @counts = {
        page_viewed: counts_query['page_viewed'] || 0,
        product_viewed: counts_query['product_viewed'] || 0,
        added_to_cart: counts_query['product_added_to_cart'] || 0,
        checkout_started: counts_query['checkout_started'] || 0,
        checkout_completed: counts_query['checkout_completed'] || 0
      }

      @prev_counts = {
        page_viewed: prev_counts_query['page_viewed'] || 0,
        product_viewed: prev_counts_query['product_viewed'] || 0,
        added_to_cart: prev_counts_query['product_added_to_cart'] || 0,
        checkout_started: prev_counts_query['checkout_started'] || 0,
        checkout_completed: prev_counts_query['checkout_completed'] || 0
      }

      if @counts.values.sum.zero? && @prev_counts.values.sum.zero?
        @empty_state = true
        @empty_message = "Nenhum evento encontrado para #{@client.name} no período selecionado."
        return
      end

      @empty_state = false

      page = @counts[:page_viewed].to_f

      @conversion = {
        product_viewed: page.zero? ? 0 : (@counts[:product_viewed] / page * 100).round(2),
        added_to_cart: page.zero? ? 0 : (@counts[:added_to_cart] / page * 100).round(2),
        checkout_started: page.zero? ? 0 : (@counts[:checkout_started] / page * 100).round(2),
        checkout_completed: page.zero? ? 0 : (@counts[:checkout_completed] / page * 100).round(2)
      }

      @dropoff = {
        page_to_product: if @counts[:page_viewed] > 0
                           (100 - (@counts[:product_viewed].to_f / @counts[:page_viewed] * 100)).round(1)
                         else
                           0
                         end,
        product_to_cart: if @counts[:product_viewed] > 0
                           (100 - (@counts[:added_to_cart].to_f / @counts[:product_viewed] * 100)).round(1)
                         else
                           0
                         end,
        cart_to_checkout: if @counts[:added_to_cart] > 0
                            (100 - (@counts[:checkout_completed].to_f / @counts[:added_to_cart] * 100)).round(1)
                          else
                            0
                          end
      }

      @unique_sessions       = base_scope.distinct.count(:session_id)
      @prev_unique_sessions  = prev_scope.distinct.count(:session_id)

      @funnel = session_funnel(base_scope, prev_scope)
      purchase = @funnel.last
      cart = @funnel.find { |step| step[:key] == :cart }
      @conversion_rate      = purchase[:pct_total]
      @prev_conversion_rate = rate(purchase[:prev_count], @prev_unique_sessions)
      @abandoned_carts      = [cart[:count] - purchase[:count], 0].max
      @abandoned_rate       = rate(@abandoned_carts, cart[:count])
      @orders_summary       = orders_summary(range, prev_range)

      @devices = { mobile: 0, desktop: 0, tablet: 0 }
      base_scope
        .select("DISTINCT ON (session_id) session_id, context->>'navigator' as nav")
        .order(:session_id, :created_at)
        .each do |row|
          ua = JSON.parse(row.nav)["userAgent"] rescue nil
          next unless ua

          if ua =~ /Mobile|Android.*Mobile|iPhone|iPod/i
            @devices[:mobile] += 1
          elsif ua =~ /iPad|Android(?!.*Mobile)|Tablet/i
            @devices[:tablet] += 1
          else
            @devices[:desktop] += 1
          end
        end

      @top_products_viewed = fetch_top_products(base_scope, "product_viewed")
      @top_products_carted = fetch_top_products(base_scope, "product_added_to_cart")

      hourly_query = base_scope
                     .group("EXTRACT(HOUR FROM created_at - INTERVAL '3 hours')::int")
                     .count

      @hourly_events = (0..23).map { |h| [h, hourly_query[h] || 0] }.to_h

      weekday_query = base_scope
                      .group("EXTRACT(DOW FROM created_at - INTERVAL '3 hours')::int")
                      .count

      weekday_names = { 0 => "Dom", 1 => "Seg", 2 => "Ter", 3 => "Qua", 4 => "Qui", 5 => "Sex", 6 => "Sab" }
      @weekday_events = weekday_names.map { |k, v| { day: v, count: weekday_query[k] || 0 } }

      @referrers = Hash.new(0)
      base_scope
        .where(kind: "page_viewed")
        .where("context->'document'->>'referrer' IS NOT NULL AND context->'document'->>'referrer' != ''")
        .select("DISTINCT ON (session_id) session_id, context->'document'->>'referrer' as ref")
        .order(:session_id, :created_at)
        .each do |row|
          ref = row.ref
          next if ref.blank?

          begin
            host = URI.parse(ref).host&.gsub(/^www\./, '') || "direto"
          rescue
            host = "outro"
          end
          source = case host
                   when /google/i          then "Google"
                   when /facebook|fb/i     then "Facebook"
                   when /instagram/i       then "Instagram"
                   when /tiktok/i          then "TikTok"
                   when /youtube/i         then "YouTube"
                   when /twitter|x\.com/i  then "Twitter/X"
                   when /bing/i            then "Bing"
                   when /pinterest/i       then "Pinterest"
                   when "", nil            then "Direto"
                   else host.truncate(20)
                   end
          @referrers[source] += 1
        end
      @referrers = @referrers.sort_by { |_, v| -v }.first(6).to_h

      @avg_times = calculate_avg_times(@client.id, range)

      @daily_events = base_scope
                      .where(kind: %w[page_viewed product_viewed product_added_to_cart checkout_completed])
                      .group("DATE(created_at - INTERVAL '3 hours')", :kind)
                      .count

      @sessions = fetch_sessions(@client.id, range)
    end

    FUNNEL_STEPS = [
      { key: :sessions, label: 'Sessões', kind: nil },
      { key: :product, label: 'Viram produto', kind: 'product_viewed' },
      { key: :cart, label: 'Adicionaram ao carrinho', kind: 'product_added_to_cart' },
      { key: :checkout, label: 'Iniciaram o checkout', kind: 'checkout_started' },
      { key: :purchase, label: 'Compraram', kind: 'checkout_completed' }
    ].freeze

    # Funil por sessão: cada etapa conta sessões únicas que tiveram o evento,
    # então todas as porcentagens têm a mesma base e uma etapa explica a outra.
    def session_funnel(base_scope, prev_scope)
      kinds = FUNNEL_STEPS.filter_map { |step| step[:kind] }
      current = base_scope.where(kind: kinds).group(:kind).distinct.count(:session_id)
      previous = prev_scope.where(kind: kinds).group(:kind).distinct.count(:session_id)

      steps = FUNNEL_STEPS.map do |step|
        count = step[:kind] ? current.fetch(step[:kind], 0) : @unique_sessions
        prev_count = step[:kind] ? previous.fetch(step[:kind], 0) : @prev_unique_sessions
        step.merge(count: count, prev_count: prev_count)
      end

      steps.each_with_index.map do |step, index|
        before = index.zero? ? step : steps[index - 1]
        step.merge(pct_total: rate(step[:count], @unique_sessions),
                   pct_step: index.zero? ? 100.0 : rate(step[:count], before[:count]),
                   lost: index.zero? ? 0 : [before[:count] - step[:count], 0].max,
                   change: change(step[:count], step[:prev_count]))
      end
    end

    # Pedidos que a Shopify registrou no período (todos os canais), para
    # completar o funil do pixel com venda e receita de verdade.
    def orders_summary(range, prev_range)
      scope = Order.where(client_id: @client.id, cancelled_at: nil)
      current = scope.where(shopify_creation_date: range)
      previous = scope.where(shopify_creation_date: prev_range)
      revenue = current.sum(:total_price).to_d
      prev_revenue = previous.sum(:total_price).to_d
      count = current.count

      { count: count, revenue: revenue, revenue_change: change(revenue, prev_revenue),
        average_ticket: count.positive? ? (revenue / count).round(2) : 0,
        revenue_per_session: @unique_sessions.positive? ? (revenue / @unique_sessions).round(2) : 0 }
    end

    def rate(part, total)
      total.to_f.positive? ? (part.to_f / total * 100).round(2) : 0.0
    end

    def change(current, previous)
      return nil unless previous.to_f.positive?

      ((current.to_f - previous.to_f) / previous.to_f * 100).round(1)
    end

    def fetch_top_products(scope, kind)
      product_id_path =
        if kind == "product_added_to_cart"
          "data->'cartLine'->'merchandise'->'product'->>'id'"
        else
          "data->'productVariant'->'product'->>'id'"
        end

      counts = scope.where(kind: kind)
                    .where("#{product_id_path} IS NOT NULL")
                    .group(Arel.sql(product_id_path))
                    .order(Arel.sql('COUNT(*) DESC'))
                    .limit(5)
                    .count

      return [] if counts.empty?

      event_data = scope.where(kind: kind)
                        .where("#{product_id_path} IN (?)", counts.keys.compact)
                        .select("DISTINCT ON (#{product_id_path}) #{product_id_path} AS product_id, data")
                        .order(Arel.sql("#{product_id_path}"))
                        .each_with_object({}) do |row, h|
                          h[row.product_id] = begin
                            row.data.is_a?(Hash) ? row.data : JSON.parse(row.data.to_s)
                          rescue
                            {}
                          end
                        end

      counts.map do |product_id, count|
        product = Product.find_by(shopify_product_id: product_id)
        payload = event_data[product_id] || {}

        if kind == "product_added_to_cart"
          variant_data = payload.dig("cartLine", "merchandise") || {}
          product_data = variant_data.dig("product") || {}
          image_src    = variant_data.dig("image", "src")
          price        = variant_data.dig("price", "amount")&.to_f
        else
          variant_data = payload.dig("productVariant") || {}
          product_data = variant_data.dig("product") || {}
          image_src    = variant_data.dig("image", "src")
          price        = variant_data.dig("price", "amount")&.to_f
        end

        title = product&.shopify_product_name ||
                product_data["title"] ||
                variant_data["title"] ||
                (variant_data["sku"].present? ? "SKU: #{variant_data["sku"]}" : nil) ||
                (product_id.present? ? "ID #{product_id}" : "Produto")

        image = product&.image_url || image_src
        sku   = variant_data["sku"]

        {
          id: product_id,
          title: title,
          sku: sku,
          image: image,
          price: product&.price || price,
          count: count
        }
      end
    end

    def calculate_avg_times(client_id, range)
      # Uma única query agregada para calcular tempos médios por sessão
      sql = <<-SQL
        SELECT
          session_id,
          MIN(CASE WHEN kind = 'page_viewed' THEN created_at END) as page_time,
          MIN(CASE WHEN kind = 'product_viewed' THEN created_at END) as product_time,
          MIN(CASE WHEN kind = 'product_added_to_cart' THEN created_at END) as cart_time,
          MIN(CASE WHEN kind = 'checkout_completed' THEN created_at END) as checkout_time
        FROM shopify_events
        WHERE client_id = :client_id
          AND created_at BETWEEN :start_at AND :end_at
          AND kind IN ('page_viewed', 'product_viewed', 'product_added_to_cart', 'checkout_completed')
        GROUP BY session_id
      SQL

      results = ShopifyEvent.find_by_sql([sql, { client_id: client_id, start_at: range.first, end_at: range.last }])

      times = { page_to_product: [], product_to_cart: [], cart_to_checkout: [] }

      results.each do |row|
        page_time    = row[:page_time]
        product_time = row[:product_time]
        cart_time    = row[:cart_time]
        checkout_time = row[:checkout_time]

        times[:page_to_product] << ((product_time - page_time) / 60).round(1) if page_time && product_time
        times[:product_to_cart] << ((cart_time - product_time) / 60).round(1) if product_time && cart_time
        times[:cart_to_checkout] << ((checkout_time - cart_time) / 60).round(1) if cart_time && checkout_time
      end

      {
        page_to_product: average(times[:page_to_product]),
        product_to_cart: average(times[:product_to_cart]),
        cart_to_checkout: average(times[:cart_to_checkout])
      }
    end

    def average(values)
      return 0 unless values.any?

      (values.sum / values.size).round(1)
    end

    def fetch_sessions(client_id, range)
      sql = <<-SQL
        SELECT
          session_id,
          MIN(created_at) as started_at,
          MAX(created_at) as last_at,
          COUNT(*) as event_count,
          ARRAY_AGG(DISTINCT kind ORDER BY kind) as kinds_arr,
          (SELECT shop_domain FROM shopify_events e2
           WHERE e2.session_id = shopify_events.session_id
             AND e2.client_id = :client_id
             AND e2.created_at BETWEEN :start_at AND :end_at
           ORDER BY e2.created_at ASC LIMIT 1) as shop_domain,
          (SELECT context->>'navigator' FROM shopify_events e3
           WHERE e3.session_id = shopify_events.session_id
             AND e3.client_id = :client_id
             AND e3.created_at BETWEEN :start_at AND :end_at
           ORDER BY e3.created_at ASC LIMIT 1) as first_context
        FROM shopify_events
        WHERE client_id = :client_id
          AND created_at BETWEEN :start_at AND :end_at
        GROUP BY session_id
        ORDER BY MAX(created_at) DESC
        LIMIT 50
      SQL

      results = ShopifyEvent.find_by_sql([sql, { client_id: client_id, start_at: range.first, end_at: range.last }])

      results.map do |row|
        ua = begin
          ctx = row[:first_context].is_a?(String) ? JSON.parse(row[:first_context]) : row[:first_context]
          ctx["userAgent"] || ""
        rescue
          ""
        end

        device = if ua =~ /Mobile|Android.*Mobile|iPhone|iPod/i
                   "Mobile"
                 elsif ua =~ /iPad|Android(?!.*Mobile)|Tablet/i
                   "Tablet"
                 else
                   "Desktop"
                 end

        kinds = row[:kinds_arr] || []
        abandoned = !kinds.include?("checkout_completed")
        started_at = row[:started_at]
        last_at = row[:last_at]

        {
          session_id: row[:session_id],
          shop_domain: row[:shop_domain],
          started_at: started_at,
          last_at: last_at,
          duration_min: started_at && last_at ? ((last_at - started_at) / 60).round(1) : 0,
          event_count: row[:event_count].to_i,
          last_kinds: kinds.last(4),
          device: device,
          abandoned: abandoned
        }
      end
    end
  end
end
