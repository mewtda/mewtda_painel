module Sales
  # Curva ABC dos produtos da loja num período: ordena os produtos pelo faturamento (itens dos pedidos não
  # cancelados) e classifica pelo acumulado — A até 80% do faturamento, B até 95%, C o resto. Produto do
  # catálogo sem venda no período fica fora da curva (conta em "sem venda"). Agrupa as variantes pelo produto
  # da Shopify; item sem produto cadastrado agrupa pelo SKU.
  class ProductAbc
    PRESETS = {
      '30' => '30 dias', '90' => '90 dias', '180' => '6 meses', '365' => '12 meses',
      'mes' => 'Este mês', 'mes_passado' => 'Mês passado'
    }.freeze
    DEFAULT_PRESET = '90'.freeze
    LIMITS = { 'A' => 80.0, 'B' => 95.0 }.freeze
    CLASSES = {
      'A' => { label: 'Curva A', hint: 'Produtos que fazem até 80% do faturamento' },
      'B' => { label: 'Curva B', hint: 'Os próximos 15% do faturamento' },
      'C' => { label: 'Curva C', hint: 'Os últimos 5% do faturamento' }
    }.freeze
    KEY_SQL = "COALESCE(products.shopify_product_id, 'sku:' || COALESCE(order_items.sku, 'sem-sku'))".freeze

    Item = Struct.new(:key, :name, :image_url, :revenue, :units, :orders, :share, :cumulative, :rank, :curve,
                      keyword_init: true) do
      def average_price = units.positive? ? revenue / units : 0
    end

    attr_reader :client, :from, :to, :preset

    def self.period_for(preset, from: nil, to: nil, today: Time.zone.today)
      first = SiteSummary.parse_date(from)
      last = SiteSummary.parse_date(to)
      return [first, [last, today].min, nil] if first && last && first <= last

      preset = DEFAULT_PRESET unless PRESETS.key?(preset)
      range = case preset
              when 'mes' then [today.beginning_of_month, today]
              when 'mes_passado' then [today.prev_month.beginning_of_month, today.prev_month.end_of_month]
              else [today - (preset.to_i - 1), today]
              end
      [*range, preset]
    end

    def initialize(client:, preset: nil, from: nil, to: nil)
      @client = client
      @from, @to, @preset = self.class.period_for(preset, from:, to:)
    end

    def days = (to - from).to_i + 1

    def items
      @items ||= begin
        rows = sales_rows
        total = rows.sum { |row| row[:revenue] }
        running = 0.0
        rows.each_with_index.map do |row, index|
          share = total.positive? ? row[:revenue] / total * 100 : 0
          before = running
          running += share
          Item.new(**row, share:, cumulative: running, rank: index + 1, curve: curve_for(before))
        end
      end
    end

    # Curva de cada produto da Shopify (para a aba Produtos): { shopify_product_id => 'A' }.
    def curve_by_product_id = items.to_h { |item| [item.key, item.curve] }

    def revenue = items.sum(&:revenue)
    def units = items.sum(&:units)
    def sold_count = items.size

    def orders_count
      @orders_count ||= item_scope.distinct.count('order_items.order_id')
    end

    def catalog_count
      @catalog_count ||= Product.where(client_id: client.id).where.not(shopify_product_id: nil)
                                .distinct.count(:shopify_product_id)
    end

    # Produtos do catálogo que não venderam nada no período.
    def unsold_count
      sold = items.map(&:key)
      [catalog_count - sold.count { |key| !key.start_with?('sku:') }, 0].max
    end

    def summary
      @summary ||= CLASSES.keys.index_with do |curve|
        list = items.select { |item| item.curve == curve }
        { count: list.size, revenue: list.sum(&:revenue), units: list.sum(&:units),
          share_of_products: sold_count.positive? ? list.size * 100.0 / sold_count : 0,
          share_of_revenue: revenue.positive? ? list.sum(&:revenue) * 100 / revenue : 0 }
      end
    end

    private

    def curve_for(cumulative_before)
      return 'A' if cumulative_before < LIMITS['A']
      return 'B' if cumulative_before < LIMITS['B']

      'C'
    end

    # Item sem product_id (comum em pedidos importados antes do produto existir) acha o produto da loja pelo SKU;
    # LIMIT 1 evita contar duas vezes quando o SKU se repete no catálogo.
    PRODUCT_JOIN = <<~SQL.squish.freeze
      LEFT JOIN LATERAL (
        SELECT p.shopify_product_id, p.shopify_product_name, p.image_url FROM products p
        WHERE p.client_id = orders.client_id
          AND (p.id = order_items.product_id OR (order_items.product_id IS NULL AND p.sku = order_items.sku))
        ORDER BY (p.id = order_items.product_id) DESC, p.id
        LIMIT 1
      ) products ON TRUE
    SQL

    def sales_rows
      item_scope.joins(PRODUCT_JOIN)
                .group(Arel.sql(KEY_SQL))
                .order(Arel.sql('SUM(order_items.price * order_items.quantity) DESC'))
                .pluck(Arel.sql(KEY_SQL),
                       Arel.sql("COALESCE(MAX(products.shopify_product_name), MAX(order_items.sku), 'Sem nome')"),
                       Arel.sql('MAX(products.image_url)'),
                       Arel.sql('SUM(order_items.price * order_items.quantity)'),
                       Arel.sql('SUM(order_items.quantity)'),
                       Arel.sql('COUNT(DISTINCT order_items.order_id)'))
                .filter_map do |key, name, image, total, units, orders|
                  next unless total.to_f.positive?

                  { key:, name:, image_url: image, revenue: total.to_f, units: units.to_i, orders: orders.to_i }
                end
    end

    def item_scope
      OrderItem.joins(:order)
               .merge(Order.not_cancelled.where(client_id: client.id, shopify_creation_date: time_range))
               .where(canceled: [false, nil])
    end

    # Datas dos pedidos em UTC; a loja opera no horário de Brasília.
    def time_range
      zone = ActiveSupport::TimeZone[LocalDate::TIME_ZONE]
      zone.local(from.year, from.month, from.day)..zone.local(to.year, to.month, to.day).end_of_day
    end
  end
end
