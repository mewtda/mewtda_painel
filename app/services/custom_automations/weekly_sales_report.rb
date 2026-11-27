module CustomAutomations
  # Relatório semanal por e-mail (feito para a Fernanda Farah): toda segunda às 8h manda para a lista de
  # destinatários configurada na tela de Automações personalizadas o resumo da semana anterior (segunda a
  # domingo) — faturamento, pedidos, ticket, peças, os produtos mais vendidos — e as variantes ativas da loja
  # com estoque baixo, lidas na hora da Shopify.
  #
  # Rotina registrada em Registry::ROUTINES; o RoutineJob roda a cada 10 min e o envio só sai uma vez por
  # semana (CustomAutomationSetting#last_run_at). "Enviar agora" (force) manda na hora, mesmo já enviado.
  class WeeklySalesReport
    KIND = 'weekly_sales_report'.freeze
    SEND_HOUR = 8
    TOP_PRODUCTS = 20
    LOW_STOCK_ROWS = 100
    LOW_STOCK_PAGES = 8

    Variant = Struct.new(:product, :variant, :sku, :quantity, :sold, :image_url, keyword_init: true)

    attr_reader :client, :from, :to

    def initialize(client, force: false, now: Time.current, shopify: nil)
      @client = client
      @force = force
      @now = now.in_time_zone(Sales::LocalDate::TIME_ZONE)
      @shopify = shopify
      @to = @now.to_date.beginning_of_week(:monday) - 1
      @from = @to - 6
    end

    def setting
      @setting ||= CustomAutomationSetting.for(client, KIND)
    end

    # Retorna quantos e-mails saíram (nil quando não era hora de enviar).
    def call
      return if setting.recipients.empty?
      return unless @force || (setting.enabled? && due?)

      html = to_html
      sender = Ses::SendEmailService.new(client, shared: true)
      sent = setting.recipients.count { |to| sender.call(to:, subject:, html_body: html) }
      setting.update!(last_run_at: @now)
      Rails.logger.info("[WeeklySalesReport] client #{client.id}: #{sent}/#{setting.recipients.size} enviados")
      sent
    end

    # Segunda, a partir das 8h, e ainda não saiu nesta semana.
    def due?
      slot = @now.beginning_of_week(:monday).change(hour: SEND_HOUR)
      @now.monday? && @now >= slot && (setting.last_run_at.nil? || setting.last_run_at < slot)
    end

    def subject
      "Resumo da semana #{from.strftime('%d/%m')} a #{to.strftime('%d/%m')} · #{client.name}"
    end

    def to_html
      ApplicationController.render(template: 'custom_automations/routines/weekly_sales_report', layout: false,
                                   locals: { report: self })
    end

    def kpis
      @kpis ||= dashboard.kpis
    end

    def units = abc.units

    def top_products = abc.items.first(TOP_PRODUCTS)

    def low_stock_limit = setting.low_stock_limit

    # Variantes de produtos ativos com estoque controlado e até o limite; as que venderam na semana primeiro.
    def low_stock
      @low_stock ||= fetch_low_stock.sort_by { |v| [-v.sold, v.quantity, v.product.to_s] }
    end

    def low_stock_error
      low_stock
      @low_stock_error
    end

    def store_url = client.storefront_url

    private

    def dashboard
      @dashboard ||= Sales::OrdersDashboard.new(client:, from: from.iso8601, to: to.iso8601)
    end

    def abc
      @abc ||= Sales::ProductAbc.new(client:, from: from.iso8601, to: to.iso8601)
    end

    def fetch_low_stock
      variants = []
      cursor = nil
      LOW_STOCK_PAGES.times do
        page = shopify.query(low_stock_query(cursor))['productVariants']
        variants.concat(page['nodes'].filter_map { |node| build_variant(node) })
        break unless page.dig('pageInfo', 'hasNextPage')

        cursor = page.dig('pageInfo', 'endCursor')
      end
      variants.first(LOW_STOCK_ROWS * 3)
    rescue StandardError => e
      @low_stock_error = e.message.truncate(200)
      []
    end

    def build_variant(node)
      return if node.dig('inventoryItem', 'tracked') == false
      return unless node.dig('product', 'status') == 'ACTIVE'

      Variant.new(product: node.dig('product', 'title'), variant: variant_title(node['title']), sku: node['sku'],
                  quantity: node['inventoryQuantity'].to_i, sold: sold_by_sku[node['sku']].to_i,
                  image_url: node.dig('image', 'url') || node.dig('product', 'featuredImage', 'url'))
    end

    def variant_title(title) = (title unless title.to_s == 'Default Title')

    def low_stock_query(cursor)
      after = cursor ? ", after: #{cursor.to_json}" : ''
      search = "inventory_quantity:<=#{low_stock_limit} AND product_status:active"
      <<~GRAPHQL
        {
          productVariants(first: 250#{after}, query: #{search.to_json}) {
            pageInfo { hasNextPage endCursor }
            nodes {
              title sku inventoryQuantity
              inventoryItem { tracked }
              image { url(transform: { maxWidth: 120 }) }
              product { title status featuredImage { url(transform: { maxWidth: 120 }) } }
            }
          }
        }
      GRAPHQL
    end

    def sold_by_sku
      @sold_by_sku ||= OrderItem.joins(:order)
                                .merge(Order.not_cancelled.where(client_id: client.id,
                                                                 shopify_creation_date: week_range))
                                .where(canceled: [false, nil]).where.not(sku: [nil, ''])
                                .group(:sku).sum(:quantity)
    end

    def week_range
      zone = ActiveSupport::TimeZone[Sales::LocalDate::TIME_ZONE]
      zone.local(from.year, from.month, from.day)..zone.local(to.year, to.month, to.day).end_of_day
    end

    def shopify
      @shopify ||= Shopify::Client.new(client)
    end
  end
end
