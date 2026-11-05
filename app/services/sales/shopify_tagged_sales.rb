module Sales
  # Vendas por tag direto do relatório da Shopify, para a meta por tag bater com
  # o que a loja mostra (vendas totais, fuso de São Paulo, em BRL).
  class ShopifyTaggedSales
    def initialize(client:, from:, to:, tags:, runner: nil)
      @from = from
      @to = to
      @tags = ShopifyReport.tags(tags)
      @report = ShopifyReport.new(client: client, runner: runner)
    end

    # => BigDecimal com o total das tags no período, ou nil se não der para consultar.
    def total
      return nil if @tags.empty?

      rows = @report.rows(shopifyql)
      return nil if rows.nil?
      # Linhas vazias = nenhum pedido com as tags no período.
      return BigDecimal('0') if rows.empty?

      BigDecimal(rows.first['total_sales__totals'].to_s)
    end

    def shopifyql
      list = @tags.map { |t| "'#{t}'" }.join(', ')
      "FROM sales SHOW total_sales, orders WHERE #{ShopifyReport.tag_condition(@tags)} " \
        "GROUP BY order_tag WITH TOTALS, #{ShopifyReport::WITH_OPTIONS} HAVING order_tag IN (#{list}) " \
        "#{ShopifyReport.range(@from, @to)}"
    end
  end
end
