module BackInStock
  class Attribution
    WINDOW_DAYS = 7
    SQL = <<~SQL.squish.freeze
      FROM back_in_stock_alerts a
      JOIN customer_profiles cp ON cp.client_id = a.client_id AND LOWER(cp.email) = a.email
      JOIN orders o ON o.client_id = a.client_id AND o.cancelled_at IS NULL
        AND (o.customer_id = cp.customer_id OR o.customer_id = ANY(cp.merged_customer_ids))
      JOIN order_items oi ON oi.order_id = o.id
      JOIN products p ON p.id = oi.product_id AND p.shopify_variant_id = a.shopify_variant_id::text
      WHERE a.client_id = :client_id AND a.status = 'notified' AND a.notified_at IS NOT NULL
        AND o.shopify_creation_date >= a.notified_at
        AND o.shopify_creation_date < a.notified_at + INTERVAL '#{WINDOW_DAYS} days'
    SQL

    def initialize(client)
      @client = client
    end

    def orders(range)
      query = "SELECT DISTINCT ON (o.id) o.id, o.total_price, o.shopify_creation_date AS ordered_at #{SQL} " \
              'AND o.shopify_creation_date BETWEEN :from AND :to ORDER BY o.id, a.notified_at'
      Order.find_by_sql([query, binds(range)])
    end

    def ordered_alert_ids(created_at: nil, notified_at: nil)
      column, range = created_at ? ['a.created_at', created_at] : ['a.notified_at', notified_at]
      query = "SELECT DISTINCT a.id #{SQL}#{" AND #{column} BETWEEN :from AND :to" if range}"
      connection.select_values(ActiveRecord::Base.sanitize_sql_array([query, binds(range)]))
    end

    private

    attr_reader :client

    def connection = ActiveRecord::Base.connection

    def binds(range)
      { client_id: client.id, from: range&.begin || Time.zone.at(0), to: range&.end || Time.current }
    end
  end
end
