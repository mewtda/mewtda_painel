module Customers
  # Atualiza o consentimento de e-mail marketing dos clientes que mudaram na
  # Shopify nos últimos dias (inscrição ou cancelamento feitos depois da compra).
  # Olha uma janela com sobreposição, então repetir a execução não faz mal.
  class SyncMarketingJob < ApplicationJob
    queue_as :default

    WINDOW = 2.days
    PAGE_SIZE = 250
    FIELDS = 'id,email_marketing_consent,accepts_marketing'.freeze

    def perform(client_id = nil)
      clients = Client.where(active: true)
      clients = clients.where(id: client_id) if client_id

      clients.find_each do |client|
        next unless client.shopify_configured?

        changed = update_states(fetch_changed(client))
        Customers::RefreshProfilesJob.perform_later(client.id) if changed.positive?
      rescue StandardError => e
        Rails.logger.error "[Customers::SyncMarketing] client #{client.id}: #{e.class}: #{e.message}"
      end
    end

    def fetch_changed(client)
      session = ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url, access_token: client.shopify_access_token)
      api = ShopifyAPI::Clients::Rest::Admin.new(session:)
      query = { limit: PAGE_SIZE, fields: FIELDS, updated_at_min: WINDOW.ago.iso8601 }
      customers = []

      loop do
        response = api.get(path: 'customers', query:, tries: Shopify::Orders::API_TRIES)
        customers.concat(response.body['customers'])
        break unless response.next_page_info

        query = { limit: PAGE_SIZE, fields: FIELDS, page_info: response.next_page_info }
        sleep(Shopify::Orders::API_PAUSE)
      end

      customers
    end

    private

    def update_states(shopify_customers)
      shopify_customers.group_by { |data| Shopify::Orders.marketing_state(data) }.sum do |state, group|
        next 0 unless state

        ids = group.map { |data| data['id'].to_s }
        Customer.where(shopify_customer_id: ids).where.not(email_marketing_state: state)
                .or(Customer.where(shopify_customer_id: ids, email_marketing_state: nil))
                .update_all(email_marketing_state: state, updated_at: Time.current)
      end
    end
  end
end
