module Segments
  # Tags dos clientes da base da loja (perfis e todos os cadastros mesclados),
  # das mais usadas para as menos usadas. Mesma tag com grafia diferente vira uma só.
  class CustomerTagOptions
    LIMIT = 500

    def initialize(client)
      @client = client
    end

    def call
      sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL, { client_id: @client.id, limit: LIMIT }])
        SELECT MIN(BTRIM(customer_tag)) AS tag, COUNT(DISTINCT c.id) AS total
        FROM customers c
        CROSS JOIN LATERAL unnest(string_to_array(c.tags, ',')) AS customer_tag
        WHERE c.id IN (SELECT unnest(cp.merged_customer_ids || cp.customer_id) FROM customer_profiles cp
                       WHERE cp.client_id = :client_id)
          AND BTRIM(customer_tag) <> ''
        GROUP BY LOWER(BTRIM(customer_tag))
        ORDER BY total DESC, tag
        LIMIT :limit
      SQL
      ActiveRecord::Base.connection.select_rows(sql).map { |tag, _| { key: tag, label: tag } }
    end
  end
end
