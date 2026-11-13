module Customers
  # Recalcula customer_profiles de uma loja a partir dos pedidos não
  # cancelados: totais, datas, ticket médio e notas RFM.
  #
  # R (recência) e M (valor) são quintis dentro da própria loja (5 = melhor);
  # F (frequência) é o número de compras, limitado a 5. O perfil vem da grade
  # CustomerProfile::RFM_GRID (R x F).
  class RefreshProfiles
    def initialize(client)
      @client = client
    end

    def call
      started = Time.current
      CustomerProfile.connection.exec_query(upsert_sql(started), 'Customers::RefreshProfiles')
      # Quem não tem mais pedido válido (ex.: todos cancelados) sai da base.
      CustomerProfile.where(client_id: @client.id).where(refreshed_at: ...started).delete_all
      CustomerProfile.where(client_id: @client.id).count
    end

    private

    ORDER_DATE = 'COALESCE(o.shopify_creation_date, o.created_at)'.freeze

    def upsert_sql(now)
      ActiveRecord::Base.sanitize_sql_array([<<~SQL, { client_id: @client.id, now: now }])
        WITH stats AS (
          SELECT o.customer_id,
                 COUNT(*) AS orders_count,
                 COALESCE(SUM(o.total_price), 0) AS total_spent,
                 MIN(#{ORDER_DATE}) AS first_order_at,
                 MAX(#{ORDER_DATE}) AS last_order_at,
                 (ARRAY_AGG(o.total_price ORDER BY #{ORDER_DATE} DESC))[1] AS last_order_total,
                 COUNT(*) FILTER (WHERE COALESCE(o.discount_code, '') <> '') AS coupons_used
          FROM orders o
          WHERE o.client_id = :client_id AND o.customer_id IS NOT NULL AND o.cancelled_at IS NULL
          GROUP BY o.customer_id
        ), scored AS (
          SELECT s.*,
                 NTILE(5) OVER (ORDER BY s.last_order_at) AS r_score,
                 LEAST(s.orders_count, 5) AS f_score,
                 NTILE(5) OVER (ORDER BY s.total_spent) AS m_score
          FROM stats s
        )
        INSERT INTO customer_profiles (
          client_id, customer_id, name, email, phone, city, state,
          orders_count, total_spent, avg_ticket, last_order_total, coupons_used,
          first_order_at, last_order_at, r_score, f_score, m_score, rfm_segment,
          refreshed_at, created_at, updated_at
        )
        SELECT :client_id, sc.customer_id,
               COALESCE(NULLIF(TRIM(CONCAT_WS(' ', c.first_name, c.last_name)), ''), NULLIF(c.name, ''), c.email),
               LOWER(NULLIF(c.email, '')),
               COALESCE(NULLIF(c.phone, ''), NULLIF(c.default_address_phone, '')),
               NULLIF(c.default_address_city, ''),
               COALESCE(NULLIF(c.default_address_province_code, ''), NULLIF(c.default_address_province, '')),
               sc.orders_count, sc.total_spent, ROUND(sc.total_spent / sc.orders_count, 2),
               sc.last_order_total, sc.coupons_used, sc.first_order_at, sc.last_order_at,
               sc.r_score, sc.f_score, sc.m_score, #{segment_case},
               :now, :now, :now
        FROM scored sc
        JOIN customers c ON c.id = sc.customer_id
        ON CONFLICT (client_id, customer_id) DO UPDATE SET
          name = EXCLUDED.name, email = EXCLUDED.email, phone = EXCLUDED.phone,
          city = EXCLUDED.city, state = EXCLUDED.state,
          orders_count = EXCLUDED.orders_count, total_spent = EXCLUDED.total_spent,
          avg_ticket = EXCLUDED.avg_ticket, last_order_total = EXCLUDED.last_order_total,
          coupons_used = EXCLUDED.coupons_used, first_order_at = EXCLUDED.first_order_at,
          last_order_at = EXCLUDED.last_order_at, r_score = EXCLUDED.r_score,
          f_score = EXCLUDED.f_score, m_score = EXCLUDED.m_score,
          rfm_segment = EXCLUDED.rfm_segment, refreshed_at = EXCLUDED.refreshed_at,
          updated_at = EXCLUDED.updated_at
      SQL
    end

    # CASE gerado da grade RFM (valores fixos do código, sem entrada do usuário).
    def segment_case
      whens = CustomerProfile::RFM_GRID.flat_map do |r, row|
        row.each_with_index.map { |segment, i| "WHEN sc.r_score = #{r.to_i} AND sc.f_score = #{i + 1} THEN '#{segment}'" }
      end
      "CASE #{whens.join(' ')} END"
    end
  end
end
