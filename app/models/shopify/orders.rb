class Shopify::Orders
  require 'shopify_api'
  extend ApplicationHelper

  API_PAUSE = 0.25
  API_TRIES = 6

  class << self
    def sync_shopify_orders_to_rails(session:, client:, limit: 100, status: 'any', time_range: :all,
                                     created_at_min: nil, created_at_max: nil)
      api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

      total = 0
      @customers_synced = {}

      created_at_min ||=
        case time_range.to_sym
        when :last_3_days
          3.days.ago.iso8601
        when :last_3_hours
          3.hours.ago.iso8601
        else
          nil
        end

      order_fields = %w[
        id name created_at line_items note_attributes customer total_price subtotal_price
        total_discounts total_tax total_shipping_price_set tags cancelled_at fulfillments
        discount_codes
      ].join(',')

      query_params = {
        limit: limit,
        status: status,
        fields: order_fields
      }

      query_params[:created_at_min] = created_at_min if created_at_min.present?
      query_params[:created_at_max] = created_at_max if created_at_max.present?

      # Busca ou cria a location do client
      @location = Location.find_or_create_by!(slug: client.name.parameterize) do |loc|
        loc.name = client.name
        loc.client_id = client.id
      end

      response = api_client.get(
        path: 'orders',
        query: query_params,
        tries: API_TRIES
      )

      loop do
        response.body['orders'].each do |shopify_order|
          sleep(API_PAUSE)
          create_or_update_order_from_shopify(
            shopify_order,
            session: session,
            client: client
          )
          total += 1
        rescue StandardError => e
          Rails.logger.error(
            "[Shopify::Orders] Falha ao sincronizar pedido #{shopify_order['name']} " \
            "(client #{client.id}): #{e.class} #{e.message}"
          )
        end

        break unless response.next_page_info

        response = api_client.get(
          path: 'orders',
          query: {
            limit: limit,
            fields: order_fields,
            page_info: response.next_page_info
          },
          tries: API_TRIES
        )
      end

      @customers_synced = nil
      client.update!(orders_synced_at: Time.current)

      Rails.logger.info "[Shopify::Orders] Sincronizados #{total} pedidos para client #{client.id} (#{client.name})"
      total
    end

    # Sincroniza reembolsos processados num período, independente da data de criação do
    # pedido — reflete exatamente a linha "Sales reversals" do relatório Total Sales do
    # Shopify, que também bucketiza reembolsos pela data em que foram processados.
    # updated_at_min/max é usado (não created_at) porque um reembolso atualiza o pedido,
    # então isso pega pedidos antigos que só tiveram movimento (reembolso) no período.
    def sync_refunds_to_rails(session:, client:, processed_at_min:, processed_at_max:, limit: 250)
      api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)
      total = 0

      range_start = Time.zone.parse(processed_at_min)
      range_end = Time.zone.parse(processed_at_max)

      refund_fields = 'id,name,refunds'

      response = api_client.get(
        path: 'orders',
        query: {
          limit: limit,
          status: 'any',
          fields: refund_fields,
          updated_at_min: processed_at_min,
          updated_at_max: processed_at_max
        }
      )

      loop do
        response.body['orders'].each do |shopify_order|
          Array(shopify_order['refunds']).each do |refund|
            next if refund['processed_at'].blank?

            processed_at = Time.parse(refund['processed_at'])
            next unless processed_at.between?(range_start, range_end)

            amount = Array(refund['transactions']).sum { |t| t['amount'].to_f }
            next if amount.zero?

            order = Order.find_by(shopify_order_id: shopify_order['id'].to_s, client_id: client.id)

            r = Refund.find_or_initialize_by(client_id: client.id, shopify_refund_id: refund['id'].to_s)
            r.assign_attributes(
              order_id: order&.id,
              shopify_order_id: shopify_order['id'].to_s,
              processed_at: processed_at,
              amount: amount
            )
            r.save! if r.changed?
            total += 1
          end
        rescue StandardError => e
          Rails.logger.error(
            "[Shopify::Orders] Falha ao sincronizar reembolsos do pedido #{shopify_order['name']} " \
            "(client #{client.id}): #{e.class} #{e.message}"
          )
        end

        break unless response.next_page_info

        response = api_client.get(
          path: 'orders',
          query: {
            limit: limit,
            fields: refund_fields,
            page_info: response.next_page_info
          }
        )
      end

      client.update!(refunds_synced_at: Time.current)

      Rails.logger.info "[Shopify::Orders] Sincronizados #{total} reembolsos para client #{client.id} (#{client.name})"
      total
    end

    def create_or_update_order_from_shopify(shopify_order, session:, client:)
      shopify_order_id     = shopify_order['id'].to_s
      shopify_order_number = shopify_order['name']
      shopify_created_at   = Time.parse(shopify_order['created_at'])

      note_attributes = extract_note_attributes_from_hash(
        shopify_order['note_attributes']
      )

      staff_id   = note_attributes['staff_ID']
      staff_name = note_attributes['staff_name']
      landing_page_id = client.landing_pages.where(id: note_attributes[LandingPage::ATTRIBUTION_KEY].to_s[/\A\d+\z/])
                              .pick(:id)

      location = @location ||= Location.find_or_create_by!(slug: client.name.parameterize) do |loc|
        loc.name = client.name
        loc.client_id = client.id
      end

      customer = find_or_create_customer_from_shopify(
        shopify_order,
        session: session
      )

      fulfillment = Array(shopify_order['fulfillments']).max_by { |f| f['created_at'].to_s }

      # Busca order existente pelo shopify_order_id E client_id
      # Isso permite que diferentes clients tenham orders com mesmo shopify_order_id
      order = Order.find_or_initialize_by(
        shopify_order_id: shopify_order_id,
        client_id: client.id
      )

      # Usa os valores originais do pedido (não os current_*) porque o Shopify calcula
      # "Gross sales"/"Discounts" com base no valor histórico de criação do pedido, e
      # trata reembolsos à parte, pela data em que o reembolso foi processado (não pela
      # data do pedido) — ver Shopify::Orders.sync_refunds_to_rails.
      order.assign_attributes(
        shopify_order_number: shopify_order_number,
        staff_id: staff_id.presence || order.staff_id,
        staff_name: staff_name.presence || order.staff_name,
        landing_page_id: landing_page_id || order.landing_page_id,
        location_id: location.id,
        shopify_creation_date: shopify_created_at,
        customer_id: customer&.id,
        client_id: client.id,
        tags: shopify_order['tags'],
        discount_code: Array(shopify_order['discount_codes']).filter_map { |d| d['code'] }.join(', ').presence,
        subtotal_price: shopify_order['subtotal_price'],
        total_discounts: shopify_order['total_discounts'],
        total_price: shopify_order['total_price'],
        total_tax: shopify_order['total_tax'] || 0,
        total_shipping_price: shopify_order.dig('total_shipping_price_set', 'shop_money', 'amount') || 0,
        cancelled_at: shopify_order['cancelled_at'].presence && Time.parse(shopify_order['cancelled_at']),
        tracking_number: fulfillment&.dig('tracking_number').presence,
        tracking_company: fulfillment&.dig('tracking_company').presence,
        tracking_url: fulfillment&.dig('tracking_url').presence,
        fulfilled_at: fulfillment&.dig('created_at').presence && Time.parse(fulfillment['created_at'])
      )

      order.created_at = shopify_created_at if order.new_record?
      order.updated_at = Time.current

      order.save! if order.changed?

      existing_items = order.order_items.index_by(&:sku)

      Array(shopify_order['line_items']).each do |line_item|
        sku = line_item['sku']
        next if sku.blank?

        price    = line_item['price'].to_f
        quantity = line_item['quantity'].to_i

        item = existing_items[sku]

        if item
          if item.price != price || item.quantity != quantity
            item.update!(
              price: price,
              quantity: quantity
            )
          end
        else
          product = Product.find_by(sku: sku)

          order.order_items.create!(
            product_id: product&.id,
            sku: sku,
            price: price,
            quantity: quantity,
            canceled: false
          )
        end
      rescue StandardError => e
        Rails.logger.error "[Shopify::Orders] Erro ao processar item SKU #{sku}: #{e.message}"
        next
      end

      order
    end

    def extract_note_attributes_from_hash(note_attributes_array)
      return {} unless note_attributes_array.is_a?(Array)

      note_attributes_array.each_with_object({}) do |attr, hash|
        hash[attr['name']] = attr['value']
      end
    end

    def find_or_create_customer_from_shopify(shopify_order, session:)
      customer_stub = shopify_order['customer']
      return nil unless customer_stub

      shopify_customer_id = customer_stub['id'].to_s
      return @customers_synced[shopify_customer_id] if @customers_synced&.key?(shopify_customer_id)

      api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)

      response = api_client.get(
        path: "customers/#{shopify_customer_id}.json",
        tries: API_TRIES
      )

      shopify_customer = response.body['customer']
      return nil unless shopify_customer

      customer = Customer.find_or_initialize_by(
        shopify_customer_id: shopify_customer_id
      )

      assign_full_customer_data(customer, shopify_customer)

      customer.save! if customer.changed?

      @customers_synced[shopify_customer_id] = customer if @customers_synced
      customer
    end

    def marketing_state(data)
      consent = data['email_marketing_consent']
      return consent['state'].to_s.downcase if consent.is_a?(Hash) && consent['state'].present?

      data['accepts_marketing'] ? 'subscribed' : 'not_subscribed' if data.key?('accepts_marketing')
    end

    def assign_full_customer_data(customer, shopify_customer)
      data = shopify_customer.respond_to?(:as_json) ? shopify_customer.as_json : shopify_customer

      default_address = data['default_address'] || {}

      customer.assign_attributes(
        first_name: data['first_name'],
        last_name: data['last_name'],
        email: data['email'],
        phone: data['phone'],
        currency: data['currency'],
        tags: data['tags'],
        orders_count: data['orders_count'],
        total_spent: data['total_spent'],
        verified_email: data['verified_email'],
        email_marketing_state: marketing_state(data),
        tax_exempt: data['tax_exempt'],
        shopify_created_at: data['created_at'],
        shopify_updated_at: data['updated_at']
      )

      return unless default_address.present?

      customer.assign_attributes(
        default_address_name: default_address['name'],
        default_address_company: default_address['company'],
        default_address_phone: default_address['phone'],
        default_address_address1: default_address['address1'],
        default_address_address2: default_address['address2'],
        default_address_city: default_address['city'],
        default_address_province: default_address['province'],
        default_address_country: default_address['country'],
        default_address_zip: default_address['zip'],
        default_address_country_code: default_address['country_code'],
        default_address_province_code: default_address['province_code']
      )
    end

    def update_order_staff(shopify_order_id, staff_id:, staff_name:)
      order = Order.find_by!(shopify_order_id:)
      order.update!(staff_id:, staff_name:)
      order
    end
  end
end
