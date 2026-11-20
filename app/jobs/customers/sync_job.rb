module Customers
  # Traz os clientes da Shopify para o painel, inclusive quem nunca comprou
  # (leads de landing page, cadastros na loja): nome, contato, endereço, tags e
  # consentimento de e-mail marketing.
  #
  # Na primeira vez importa a base inteira; depois, só quem mudou desde a última
  # sincronização (com sobreposição, então repetir não faz mal). Cada execução lê
  # até BATCH_PAGES páginas e agenda a continuação, para não prender a fila.
  #
  # Não mexe em orders_count/total_spent: esses números vêm dos pedidos.
  class SyncJob < ApplicationJob
    queue_as :default

    PAGE_SIZE = 250
    BATCH_PAGES = 20
    OVERLAP = 1.hour
    FIELDS = %w[id first_name last_name email phone tags email_marketing_consent accepts_marketing currency
                verified_email tax_exempt default_address created_at updated_at].join(',').freeze

    # Sem client_id: agenda a sincronização de cada loja ativa com Shopify.
    # page_info/started_at/changed: continuação de uma leitura em andamento.
    def perform(client_id = nil, page_info = nil, started_at = nil, changed = false)
      return enqueue_all if client_id.nil?

      client = Client.find_by(id: client_id, active: true)
      return unless client&.shopify_configured?

      started_at ||= Time.current.iso8601
      page_info, saved = sync_pages(client, page_info)
      changed ||= saved.positive?

      if page_info
        self.class.perform_later(client.id, page_info, started_at, changed)
      else
        client.update_columns(customers_synced_at: Time.zone.parse(started_at))
        Customers::RefreshProfilesJob.perform_later(client.id) if changed
      end
    end

    # => [page_info da próxima página (nil no fim), quantos clientes mudaram]
    def sync_pages(client, page_info)
      api = ShopifyAPI::Clients::Rest::Admin.new(session: session_for(client))
      query = page_info ? page_query(page_info) : first_query(client)
      saved = 0

      BATCH_PAGES.times do |i|
        sleep(Shopify::Orders::API_PAUSE) if i.positive?
        response = api.get(path: 'customers', query:, tries: Shopify::Orders::API_TRIES)
        saved += save_customers(client, response.body['customers'])
        page_info = response.next_page_info
        return [nil, saved] unless page_info

        query = page_query(page_info)
      end
      [page_info, saved]
    end

    # Grava/atualiza os clientes de uma página da Shopify. => quantos mudaram.
    def save_customers(client, shopify_customers)
      shopify_customers = Array(shopify_customers)
      ids = shopify_customers.map { |data| data['id'].to_s }
      existing = Customer.where(shopify_customer_id: ids).index_by(&:shopify_customer_id)

      shopify_customers.count do |data|
        customer = existing[data['id'].to_s] || Customer.new(shopify_customer_id: data['id'].to_s)
        assign(customer, client, data)
        next false unless customer.changed?

        customer.save!
        true
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        Rails.logger.warn "[Customers::SyncJob] client #{client.id} customer #{data['id']}: #{e.message}"
        false
      end
    end

    private

    def enqueue_all
      Client.where(active: true).find_each do |client|
        self.class.perform_later(client.id) if client.shopify_configured?
      end
    end

    def session_for(client)
      ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url, access_token: client.shopify_access_token)
    end

    def first_query(client)
      query = { limit: PAGE_SIZE, fields: FIELDS }
      query[:updated_at_min] = (client.customers_synced_at - OVERLAP).iso8601 if client.customers_synced_at
      query
    end

    def page_query(page_info) = { limit: PAGE_SIZE, fields: FIELDS, page_info: }

    def assign(customer, client, data)
      customer.client_id ||= client.id
      customer.assign_attributes(
        first_name: data['first_name'], last_name: data['last_name'], email: data['email'], phone: data['phone'],
        tags: data['tags'], currency: data['currency'], verified_email: data['verified_email'],
        tax_exempt: data['tax_exempt'], shopify_created_at: data['created_at'], shopify_updated_at: data['updated_at']
      )
      state = Shopify::Orders.marketing_state(data)
      customer.email_marketing_state = state if state
      assign_address(customer, data['default_address'])
    end

    def assign_address(customer, address)
      return if address.blank?

      %w[name company phone address1 address2 city province country zip country_code province_code].each do |key|
        customer["default_address_#{key}"] = address[key]
      end
    end
  end
end
