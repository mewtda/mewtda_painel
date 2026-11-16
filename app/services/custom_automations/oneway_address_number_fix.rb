module CustomAutomations
  # OneWay: o checkout bagunça o endereço de entrega, e a etiqueta sai errada.
  # Esta rotina passa pelos pedidos recentes ainda não enviados e arruma:
  #
  # - número no complemento: "Rua Pio IV" / "210"  → "Rua Pio IV, 210" / ""
  # - número repetido:       "Av. Macuco, 212 212" / "212" → "Av. Macuco, 212" / ""
  # - complemento colado na rua: "Rua X, 385 Casa 22" / "Casa 22" → "Rua X, 385" / "Casa 22"
  # - acento em maiúscula no meio da palavra: "SÃo Paulo", "GuimarÃes" → "São Paulo", "Guimarães"
  # - grafia oficial da rua e da cidade pelo CEP (BrasilAPI/ViaCEP), quando o
  #   que foi digitado é a mesma coisa só com acento/maiúscula diferente
  #
  # Quando nem assim o endereço tem número (o CEP não informa o número da casa),
  # o pedido ganha a tag MISSING_NUMBER_TAG pra equipe falar com o cliente.
  #
  # Rotina registrada em Registry::ROUTINES e rodada pelo RoutineJob. Cada regra
  # só age quando o padrão bate, então rodar de novo no mesmo pedido não muda nada.
  class OnewayAddressNumberFix
    SEPARATORS = '\s,.;:\-–—/'.freeze
    NUMBER = %r{\d+[a-zA-Z]?|s/?n}i
    LEADING_NUMBER = /\A\s*(?:n[º°o]?\.?\s*)?(#{NUMBER})(?=[#{SEPARATORS}]|\z)[#{SEPARATORS}]*/i
    # "3 andar", "2 bloco"… não são o número da casa.
    NOT_A_HOUSE_NUMBER = /\A(?:º|°|andar|and\b|bloco|bl\b|torre)/i
    TRAILING_NUMBER = /,?\s*(?<![[:alnum:]])(#{NUMBER})\s*\z/i
    REPEATED_NUMBER = /(?<!\d)(\d+[a-zA-Z]?)(?:[\s,\-–]+\1(?![\dA-Za-z]))+/
    ACCENTED_CAPITAL = /[ÀÁÂÃÄÇÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜ]/
    FIELDS = %w[address1 address2 city].freeze
    MISSING_NUMBER_TAG = 'endereço sem número'.freeze

    ADDRESS_FIELDS = %w[firstName lastName company address1 address2 city provinceCode zip countryCodeV2 phone].freeze

    Result = Struct.new(:order_name, :before, :after, :tagged, :error, keyword_init: true)

    # Recebe { 'address1', 'address2', 'city' } (e o CEP consultado, se houver)
    # e devolve só os campos que mudaram, ou nil quando o endereço já está certo.
    def self.fix(address, cep: nil)
      before = FIELDS.to_h { |f| [f, address[f].to_s.strip] }
      after = before.transform_values { |v| fix_capitals(v) }

      street, complement = after.values_at('address1', 'address2')
      street = street.gsub(REPEATED_NUMBER, '\\1')
      street = drop_glued_complement(street, complement)
      street, complement = move_number(street, complement)
      complement = '' if complement.present? && complement.casecmp?(street[TRAILING_NUMBER, 1].to_s)

      after.merge!('address1' => street, 'address2' => complement)
      apply_cep(after, cep) if cep
      changed = after.reject { |field, value| value == before[field] }
      changed.presence
    end

    def self.missing_number?(street)
      street.to_s.strip.present? && !street.match?(TRAILING_NUMBER)
    end

    # Troca rua/cidade pela grafia oficial só quando é o mesmo nome (ignorando
    # acento, maiúscula e o tipo do logradouro faltando: "Pedroso Alvarenga"
    # vira "Rua Pedroso Alvarenga"). Nome diferente fica como o cliente digitou.
    def self.apply_cep(after, cep)
      name = after['address1'].sub(TRAILING_NUMBER, '')
      suffix = after['address1'][name.length..]
      official = cep['street'].to_s
      if official.present? && name.present? &&
         (same_text?(name, official) || plain(official).end_with?(" #{plain(name)}"))
        after['address1'] = "#{official}#{suffix}"
      end

      after['city'] = cep['city'] if cep['city'].present? && same_text?(after['city'], cep['city'])
    end

    def self.same_text?(left, right)
      plain(left) == plain(right)
    end

    def self.plain(text)
      I18n.transliterate(text.to_s).downcase.squish
    end

    # Só mexe em palavras que já têm minúscula — "SÃO PAULO" fica como está.
    def self.fix_capitals(text)
      text.gsub(/[[:alpha:]]+/) do |word|
        next word unless word.match?(/\p{Ll}/)

        word[0] + word[1..].gsub(ACCENTED_CAPITAL, &:downcase)
      end
    end

    # "Rua X, 385 Casa 22" com complemento "Casa 22" → "Rua X, 385".
    def self.drop_glued_complement(street, complement)
      return street if complement.blank?

      suffix = /[\s,\-–]+#{Regexp.escape(complement)}\z/i
      trimmed = street.sub(suffix, '')
      trimmed != street && trimmed.match?(TRAILING_NUMBER) ? trimmed : street
    end

    # "Rua Pio IV" / "210" → "Rua Pio IV, 210" / "".
    def self.move_number(street, complement)
      return [street, complement] if street.empty? || complement.empty? || street.match?(TRAILING_NUMBER)

      match = complement.match(LEADING_NUMBER)
      return [street, complement] unless match

      rest = complement[match.end(0)..].to_s.strip
      return [street, complement] if rest.match?(NOT_A_HOUSE_NUMBER)

      number = match[1].match?(%r{\As/?n\z}i) ? 'S/N' : match[1]
      ["#{street.sub(/[\s,]+\z/, '')}, #{number}", rest]
    end

    def initialize(client, lookback_hours: 72, gateway: nil, cep_lookup: CepLookup)
      @client = client
      @since = lookback_hours.to_i.hours.ago
      @gateway = gateway
      @cep_lookup = cep_lookup
    end

    def call
      gateway.unfulfilled_orders_since(@since).filter_map { |order| fix_order(order) }
    end

    # Endereço já verificado (mesmo pedido, mesmo endereço) não é consultado de
    # novo — a rotina roda a cada 10 min e o CEP/a Shopify têm limite.
    def self.checked_key(order, address)
      "oneway_address_fix:#{order['id']}:#{Digest::MD5.hexdigest(address.to_json)}"
    end

    private

    def fix_order(order)
      address = order['shippingAddress']
      return unless address

      key = self.class.checked_key(order, address)
      return if Rails.cache.exist?(key)

      result = process(order, address)
      Rails.cache.write(key, true, expires_in: 7.days) if result.nil? || result.error.nil?
      result
    end

    def process(order, address)
      changes = self.class.fix(address, cep: brazilian?(address) ? @cep_lookup.call(address['zip']) : nil)
      after = address.merge(changes || {})
      tag = self.class.missing_number?(after['address1']) && Array(order['tags']).exclude?(MISSING_NUMBER_TAG)
      return unless changes || tag

      errors = changes ? gateway.update_shipping_address(order['id'], after) : []
      errors += gateway.add_tag(order['id'], MISSING_NUMBER_TAG) if tag
      result = Result.new(order_name: order['name'], before: address.slice(*FIELDS), after: after.slice(*FIELDS),
                          tagged: tag, error: errors.presence&.join('; '))
      log(result)
      result
    end

    def brazilian?(address)
      address['countryCodeV2'].blank? || address['countryCodeV2'] == 'BR'
    end

    def log(result)
      Rails.logger.info(
        "[OnewayAddressNumberFix] #{result.order_name}: #{result.before.values.join(' / ')} → " \
        "#{result.after.values.join(' / ')}#{' [sem número: tag]' if result.tagged}" \
        "#{" (erro: #{result.error})" if result.error}"
      )
    end

    def gateway
      @gateway ||= ShopifyGateway.new(@client)
    end

    class ShopifyGateway
      PAGE_SIZE = 100

      def initialize(client)
        session = ShopifyAPI::Auth::Session.new(shop: client.shopify_shop_url,
                                                access_token: client.shopify_access_token)
        @api = ShopifyAPI::Clients::Rest::Admin.new(session: session)
      end

      def unfulfilled_orders_since(since)
        query = "created_at:>='#{since.utc.iso8601}' AND fulfillment_status:unfulfilled AND status:open"
        orders = []
        cursor = nil

        loop do
          data = graphql(<<~GRAPHQL, query: query, after: cursor).dig('data', 'orders')
            query($query: String!, $after: String) {
              orders(first: #{PAGE_SIZE}, after: $after, query: $query) {
                pageInfo { hasNextPage endCursor }
                nodes { id name tags shippingAddress { #{ADDRESS_FIELDS.join(' ')} } }
              }
            }
          GRAPHQL
          break unless data

          orders.concat(data['nodes'])
          break unless data.dig('pageInfo', 'hasNextPage')

          cursor = data.dig('pageInfo', 'endCursor')
        end

        orders
      end

      # Manda o endereço inteiro: no orderUpdate o shippingAddress substitui o atual.
      def update_shipping_address(order_id, address)
        input = address.slice(*ADDRESS_FIELDS).except('countryCodeV2')
        input['countryCode'] = address['countryCodeV2'] if address['countryCodeV2']

        body = graphql(<<~GRAPHQL, input: { id: order_id, shippingAddress: input.compact })
          mutation($input: OrderInput!) {
            orderUpdate(input: $input) { userErrors { field message } }
          }
        GRAPHQL

        top_level = Array(body['errors']).map { |e| e['message'] }
        top_level + Array(body.dig('data', 'orderUpdate', 'userErrors')).map { |e| e['message'] }
      end

      def add_tag(order_id, tag)
        body = graphql(<<~GRAPHQL, id: order_id, tags: [tag])
          mutation($id: ID!, $tags: [String!]!) {
            tagsAdd(id: $id, tags: $tags) { userErrors { field message } }
          }
        GRAPHQL

        top_level = Array(body['errors']).map { |e| e['message'] }
        top_level + Array(body.dig('data', 'tagsAdd', 'userErrors')).map { |e| e['message'] }
      end

      private

      def graphql(query, **variables)
        @api.post(path: 'graphql.json', body: { query: query, variables: variables }).body
      end
    end
  end
end
