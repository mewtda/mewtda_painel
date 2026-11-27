class Shopify::Checkouts
  require 'shopify_api'

  class << self
    # Sincroniza checkouts abertos (ainda não finalizados) via API Admin —
    # a mesma fonte que a Shopify usa pro relatório "Abandoned checkouts".
    # Exige o escopo read_checkouts (não incluído por padrão) e, pra trazer
    # telefone/e-mail, aprovação de "Protected Customer Data" da Shopify.
    #
    # Só busca os criados nos últimos `since` (a recuperação usa as últimas 24h; os 7 dias cobrem falhas
    # do job). Nas páginas seguintes vai só page_info: a Shopify recusa status/filtros junto com ele.
    def sync_abandoned_checkouts_to_rails(session:, client:, limit: 250, since: 7.days.ago)
      api_client = ShopifyAPI::Clients::Rest::Admin.new(session: session)
      total = 0

      response = api_client.get(path: 'checkouts',
                                query: { limit: limit, status: 'open', created_at_min: since.iso8601 })

      loop do
        Array(response.body['checkouts']).each do |checkout|
          create_or_update_from_shopify(checkout, client: client)
          total += 1
        end

        break unless response.next_page_info

        response = api_client.get(path: 'checkouts', query: { limit: limit, page_info: response.next_page_info })
      end

      total
    end

    private

    def create_or_update_from_shopify(checkout, client:)
      checkout_id = checkout['id'].to_s
      return if checkout_id.blank?

      record = AbandonedCheckout.find_or_initialize_by(client_id: client.id, shopify_checkout_id: checkout_id)

      record.assign_attributes(
        shopify_checkout_token: checkout['token'],
        customer_id: find_customer_id(checkout),
        email: checkout['email'],
        phone: extract_phone(checkout),
        total_price: checkout['total_price'],
        currency: checkout['currency'],
        checkout_created_at: parse_time(checkout['created_at']),
        checkout_updated_at: parse_time(checkout['updated_at']),
        recovery_url: checkout['abandoned_checkout_url'],
        completed_at: parse_time(checkout['completed_at']),
        line_items: Array(checkout['line_items']).map { |li| { title: li['title'], quantity: li['quantity'] } }
      )

      record.save!
    end

    def extract_phone(checkout)
      checkout.dig('billing_address', 'phone').presence ||
        checkout.dig('shipping_address', 'phone').presence ||
        checkout['phone'].presence
    end

    def find_customer_id(checkout)
      shopify_customer_id = checkout.dig('customer', 'id')
      return nil if shopify_customer_id.blank?

      Customer.find_by(shopify_customer_id: shopify_customer_id.to_s)&.id
    end

    def parse_time(value)
      value.present? ? Time.parse(value) : nil
    end
  end
end
