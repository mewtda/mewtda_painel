module Sales
  # Pedidos com devolução no período, direto do relatório de vendas da Shopify
  # (mesma base do "− Devoluções" do painel). Respeita o filtro de tag.
  class ShopifyReturns
    LIMIT = 1000

    def initialize(client:, from:, to:, tag: nil, runner: nil)
      @client = client
      @from = from
      @to = to
      @tag = tag
      @report = ShopifyReport.new(client: client, runner: runner)
    end

    # => { orders: [{ id:, name:, returns:, url: }], total: BigDecimal, query: String } ou nil.
    def call
      rows = @report.rows(shopifyql)
      return nil if rows.nil?

      orders = rows.map do |row|
        { id: row['order_id'].to_s, name: row['order_name'].to_s, returns: BigDecimal(row['returns'].to_s).abs,
          url: order_url(row['order_id']) }
      end
      { orders: orders, total: orders.sum(BigDecimal('0')) { |o| o[:returns] }, query: shopifyql }
    end

    def shopifyql
      @shopifyql ||= begin
        where = ''
        if @tag.present?
          tags = ShopifyReport.tags(@tag)
          where = "WHERE #{ShopifyReport.tag_condition(tags)} " if tags.any?
        end
        "FROM sales SHOW returns #{where}GROUP BY order_id, order_name WITH #{ShopifyReport::WITH_OPTIONS} " \
          "HAVING returns < 0 #{ShopifyReport.range(@from, @to)} ORDER BY returns ASC LIMIT #{LIMIT}"
      end
    end

    private

    def order_url(order_id)
      return if order_id.blank? || @client.shopify_admin_handle.blank?

      "https://admin.shopify.com/store/#{@client.shopify_admin_handle}/orders/#{order_id}"
    end
  end
end
