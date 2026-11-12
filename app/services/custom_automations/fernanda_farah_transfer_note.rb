module CustomAutomations
  # Nota de transferência mensal da Fernanda Farah: a matriz (Tiny 1) emite uma
  # NF de saída CFOP 5152 em nome da filial do e-commerce (Tiny 3) com tudo que
  # foi vendido na Shopify no período — mesmo esquema da nota Tiny 2 → Tiny 3 da
  # Chase (ChaseOrders: CreateNoteTiny2Job / EmitionNoteTiny2Job).
  #
  # Duas etapas separadas de propósito: build! inclui a nota no Tiny sem emitir
  # (fica pendente pra conferência, junto com a planilha) e emit! só transmite
  # pra SEFAZ depois que alguém aprova pela tela.
  class FernandaFarahTransferNote
    KIND = 'fernanda_farah_transfer_note'.freeze
    NATUREZA_OPERACAO = 'CFOP 5152 - Transferência de mercadoria adquirida ou recebida de terceiros'.freeze
    MAX_NFE_ITEMS = 990
    SHOP_TIME_ZONE = 'America/Sao_Paulo'.freeze
    # Sem o escopo read_all_orders a API da Shopify só devolve os últimos 60 dias.
    SHOPIFY_DEFAULT_ORDER_WINDOW = 60.days
    PAID_STATUSES = %w[paid partially_refunded].freeze

    class Error < StandardError; end

    def self.matriz_token
      ENV.fetch('FERNANDA_FARAH_TINY_MATRIZ_TOKEN', nil)
    end

    def self.ecommerce_token
      ENV.fetch('FERNANDA_FARAH_TINY_ECOMMERCE_TOKEN', nil)
    end

    def initialize(run, matriz: nil, ecommerce: nil, shopify_orders: nil, current_skus: nil)
      @run = run
      @client = run.client
      @matriz = matriz
      @ecommerce = ecommerce
      @shopify_orders = shopify_orders
      @current_skus = current_skus
    end

    def build!
      @run.update!(status: 'processing', error_message: nil)

      orders = select_orders(shopify_orders)
      items, warnings = aggregate_items(orders)
      raise Error, 'Nenhum item encontrado nos pedidos do período.' if items.empty?
      if items.size > MAX_NFE_ITEMS
        raise Error, "A nota teria #{items.size} itens — o limite da NF-e é #{MAX_NFE_ITEMS}."
      end

      warnings += enrich_from_tiny(items)
      @run.update!(items: items, warnings: warnings, orders_count: orders.size,
                   total_value: items.sum { |i| i['total'] })

      begin
        registro = matriz.create_invoice(invoice_payload(items))
      rescue Net::ReadTimeout, Net::OpenTimeout
        raise Error, 'O Tiny não respondeu a tempo ao incluir a nota — ela pode ter sido criada mesmo assim. ' \
                     'Confira as notas pendentes no Tiny da matriz antes de gerar de novo.'
      end
      @run.update!(status: 'awaiting_review', tiny_note_id: registro['id'].to_s,
                   tiny_note_number: registro['numero'].to_s, tiny_response: registro.to_json)
    rescue StandardError => e
      @run.update!(status: 'failed', error_message: "#{e.class.name.demodulize}: #{e.message}")
      raise unless e.is_a?(Error) || e.is_a?(TinyApi::Error)
    end

    def emit!
      @run.update!(status: 'emitting', error_message: nil)
      result = matriz.emit_invoice(@run.tiny_note_id)
      @run.update!(status: 'emitted', emitted_at: Time.current, tiny_response: result.to_json)
    rescue TinyApi::Error => e
      # Mesmo critério da Chase: se o Tiny diz que a nota não está mais pendente,
      # ela já foi transmitida (ex.: emitida manualmente pelo painel do Tiny).
      if e.message.include?('apenas notas pendentes ou rejeitadas podem ser enviadas')
        @run.update!(status: 'emitted', emitted_at: Time.current, tiny_response: e.message)
      else
        @run.update!(status: 'awaiting_review', error_message: e.message)
      end
    end

    private

    def matriz
      @matriz ||= TinyApi.new(self.class.matriz_token)
    end

    def ecommerce
      @ecommerce ||= TinyApi.new(self.class.ecommerce_token)
    end

    def period_range
      zone = ActiveSupport::TimeZone[SHOP_TIME_ZONE]
      zone.parse(@run.period_start.to_s).beginning_of_day..zone.parse(@run.period_end.to_s).end_of_day
    end

    # ---- Shopify --------------------------------------------------------------

    def shopify_orders
      @shopify_orders ||= fetch_shopify_orders
    end

    def fetch_shopify_orders
      raise Error, 'Shopify não configurada para este cliente.' unless @client.shopify_configured?

      ensure_order_history_access!
      session = ShopifyAPI::Auth::Session.new(shop: @client.shopify_shop_url,
                                              access_token: @client.shopify_access_token)
      api = ShopifyAPI::Clients::Rest::Admin.new(session: session)
      fields = 'id,name,created_at,cancelled_at,financial_status,line_items,refunds'
      response = api.get(path: 'orders', query: {
                           limit: 250, status: 'any', fields: fields,
                           created_at_min: period_range.begin.iso8601,
                           created_at_max: period_range.end.iso8601
                         })
      orders = []

      loop do
        orders.concat(response.body['orders'])
        break unless response.next_page_info

        response = api.get(path: 'orders', query: { limit: 250, fields: fields,
                                                    page_info: response.next_page_info })
      end

      orders
    end

    def ensure_order_history_access!
      return if period_range.begin > SHOPIFY_DEFAULT_ORDER_WINDOW.ago

      data = Shopify::Client.new(@client).query('{ currentAppInstallation { accessScopes { handle } } }')
      scopes = data.dig('currentAppInstallation', 'accessScopes').map { |s| s['handle'] }
      return if scopes.include?('read_all_orders')

      raise Error, 'O período tem pedidos com mais de 60 dias e o app da Shopify não tem o escopo ' \
                   'read_all_orders — a Shopify devolveria a lista incompleta. Adicione o escopo no app.'
    end

    def select_orders(orders)
      case @run.order_filter
      when 'paid'
        orders.select { |o| o['cancelled_at'].nil? && PAID_STATUSES.include?(o['financial_status']) }
      when 'not_cancelled'
        orders.select { |o| o['cancelled_at'].nil? }
      else
        orders
      end
    end

    # Agrupa as linhas por SKU. O preço praticado é o preço pago já descontado
    # (desconto alocado na linha), em média ponderada pela quantidade; o valor
    # na nota é esse preço × percentual configurado.
    def aggregate_items(orders)
      subtract_refunds = @run.order_filter != 'all'
      warnings = []
      grouped = {}
      skus = current_skus(orders)
      renamed = {}

      orders.each do |order|
        refunded = subtract_refunds ? refunded_quantities(order) : Hash.new(0)

        Array(order['line_items']).each do |line|
          next if line['gift_card']

          quantity = line['quantity'].to_i - refunded[line['id']]
          next unless quantity.positive?

          original_quantity = line['quantity'].to_i
          discount = Array(line['discount_allocations']).sum { |d| d['amount'].to_d }
          unit_paid = ((line['price'].to_d * original_quantity) - discount) / original_quantity

          original_sku = line['sku'].to_s.strip
          sku = skus[line['variant_id'].to_s].presence || original_sku
          renamed[original_sku] = sku if original_sku.present? && sku != original_sku
          key = sku.presence || "variant:#{line['variant_id'] || line['title']}"
          entry = grouped[key] ||= { 'sku' => sku, 'shopify_title' => line_title(line),
                                     'quantity' => 0, 'paid_value' => 0.to_d, 'orders' => [] }
          entry['quantity'] += quantity
          entry['paid_value'] += unit_paid * quantity
          entry['orders'] << order['name']
        end
      end

      items = grouped.values.sort_by { |e| [e['sku'].presence || 'zzz', e['shopify_title']] }.map do |e|
        average = (e['paid_value'] / e['quantity']).round(2)
        unit_value = (average * @run.price_percentage / 100).round(2)
        warnings << "#{e['shopify_title']} está sem SKU na Shopify." if e['sku'].blank?
        warnings << "#{e['sku'].presence || e['shopify_title']} saiu com valor zero (troca)." if unit_value.zero?

        { 'sku' => e['sku'], 'shopify_title' => e['shopify_title'], 'quantity' => e['quantity'],
          'average_price' => average.to_f, 'unit_value' => unit_value.to_f,
          'total' => (unit_value * e['quantity']).round(2).to_f, 'orders_count' => e['orders'].uniq.size }
      end

      renamed.each do |old_sku, new_sku|
        warnings << "SKU #{old_sku} dos pedidos é hoje #{new_sku} na Shopify — a nota usa #{new_sku}."
      end

      [items, warnings]
    end

    # O pedido guarda o SKU que a variação tinha na hora da venda; se o
    # cadastro mudou depois, vale o SKU atual da variação na Shopify.
    # Devolve { "variant_id" => "sku atual" }.
    def current_skus(orders)
      return @current_skus.transform_keys(&:to_s) if @current_skus

      ids = orders.flat_map { |o| Array(o['line_items']).map { |l| l['variant_id'] } }.compact.uniq
      return {} if ids.empty?

      shopify = Shopify::Client.new(@client)
      ids.each_slice(250).each_with_object({}) do |slice, acc|
        gids = slice.map { |id| %("gid://shopify/ProductVariant/#{id}") }.join(',')
        data = shopify.query("{ nodes(ids: [#{gids}]) { ... on ProductVariant { legacyResourceId sku } } }")
        Array(data['nodes']).compact.each { |v| acc[v['legacyResourceId'].to_s] = v['sku'].to_s.strip }
      end
    end

    def refunded_quantities(order)
      Array(order['refunds']).flat_map { |r| Array(r['refund_line_items']) }
                             .each_with_object(Hash.new(0)) { |rli, acc| acc[rli['line_item_id']] += rli['quantity'].to_i }
    end

    def line_title(line)
      [line['title'], line['variant_title'].presence].compact.join(' - ')
    end

    # ---- Tiny -----------------------------------------------------------------

    # Puxa NCM, GTIN, unidade, origem e nome do cadastro da matriz pelo SKU.
    def enrich_from_tiny(items)
      warnings = []

      items.each do |item|
        product = item['sku'].present? ? matriz.find_product_by_code(item['sku']) : nil

        if product
          item.merge!('tiny_found' => true, 'description' => product['nome'], 'ncm' => product['ncm'].to_s,
                      'gtin' => product['gtin'].to_s, 'unit' => product['unidade'].presence || 'UN',
                      'origin' => product['origem'].to_s, 'gross_weight' => product['peso_bruto'].to_s,
                      'net_weight' => product['peso_liquido'].to_s)
          warnings << "#{item['sku']} está sem NCM no Tiny da matriz." if item['ncm'].blank?
        else
          item.merge!('tiny_found' => false, 'description' => item['shopify_title'], 'ncm' => '', 'gtin' => '',
                      'unit' => 'UN', 'origin' => '0', 'gross_weight' => '', 'net_weight' => '')
          warnings << "#{item['sku'].presence || item['shopify_title']} não foi encontrado no Tiny da matriz."
        end
      end

      warnings
    end

    def invoice_payload(items)
      now = Time.current.in_time_zone(SHOP_TIME_ZONE)

      {
        'nota_fiscal' => {
          'tipo' => 'S',
          'natureza_operacao' => NATUREZA_OPERACAO,
          'data_emissao' => now.strftime('%d/%m/%Y'),
          'data_entrada_saida' => now.strftime('%d/%m/%Y'),
          'hora_entrada_saida' => now.strftime('%H:%M'),
          'cliente' => recipient,
          'itens' => items.map { |item| { 'item' => invoice_item(item) } },
          'frete_por_conta' => 'S',
          'valor_frete' => '0',
          'finalidade' => '1',
          'obs' => "Transferência referente às vendas do e-commerce de " \
                   "#{@run.period_start.strftime('%d/%m/%Y')} a #{@run.period_end.strftime('%d/%m/%Y')}."
        }
      }
    end

    def invoice_item(item)
      {
        'codigo' => item['sku'],
        'descricao' => item['description'],
        'unidade' => item['unit'],
        'quantidade' => item['quantity'].to_s,
        'valor_unitario' => format('%.2f', item['unit_value']),
        'tipo' => 'P',
        'origem' => item['origin'],
        'ncm' => item['ncm'],
        'gtin_ean' => item['gtin'],
        'peso_bruto' => item['gross_weight'],
        'peso_liquido' => item['net_weight']
      }
    end

    # Destinatário = a filial do e-commerce, com os dados da própria conta Tiny dela.
    def recipient
      info = ecommerce.account_info

      {
        'nome' => info['razao_social'],
        'tipo_pessoa' => 'J',
        'cpf_cnpj' => info['cnpj_cpf'],
        'ie' => info['inscricao_estadual'],
        'endereco' => info['endereco'],
        'numero' => info['numero'],
        'complemento' => info['complemento'],
        'bairro' => info['bairro'],
        'cep' => info['cep'],
        'cidade' => info['cidade'],
        'uf' => info['estado'],
        'fone' => info['fone'],
        'email' => info['email'],
        'atualizar_cliente' => 'N'
      }
    end
  end
end
