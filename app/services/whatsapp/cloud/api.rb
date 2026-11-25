module Whatsapp
  module Cloud
    # Cliente fino da API Oficial do WhatsApp (Cloud API / Graph API) com as credenciais do cliente.
    # Nunca loga corpo de requisição/resposta e remove o token de qualquer mensagem de erro.
    class Api
      BASE_URL = "https://graph.facebook.com/#{Meta::MonthlyCostFetcher::GRAPH_API_VERSION}".freeze
      TIMEOUT = 15
      BLOCKED_CODES = [131_049, 131_050, 131_047].freeze
      RATE_LIMIT_CODES = [130_429].freeze
      # Problema do modelo (pausado, desativado, excluído) ou da conta (token, bloqueio, pagamento):
      # vale para todo mundo, então o envio deve pausar em vez de marcar cada pessoa como falha.
      TEMPLATE_CODES = (132_000..132_016).to_a.freeze
      PAUSE_CODES = (TEMPLATE_CODES + [190, 10, 131_031, 131_042, 131_053, 368]).freeze

      class Error < StandardError
        attr_reader :code

        def initialize(message = nil, code: nil)
          super(message)
          @code = code
        end
      end
      class RateLimited < Error; end
      class Blocked < Error; end
      class NotConfigured < Error; end
      class Paused < Error
        def template_problem? = TEMPLATE_CODES.include?(code)
      end

      def initialize(client)
        @client = client
      end

      def configured?
        phone_id.present? && waba_id.present? && token.present?
      end

      # url_button_param: final do link do botão de URL com variável (o botão na posição url_button_index).
      def send_template(to:, name:, language:, body_params: [], url_button_param: nil, url_button_index: 0)
        template = { name:, language: { code: language } }
        components = []
        if body_params.present?
          components << { type: 'body', parameters: body_params.map { |text| { type: 'text', text: text.to_s } } }
        end
        if url_button_param.present?
          components << { type: 'button', sub_type: 'url', index: url_button_index.to_s,
                          parameters: [{ type: 'text', text: url_button_param.to_s }] }
        end
        template[:components] = components if components.any?
        number = Whatsapp::Phone.normalize(to)&.delete_prefix('+') || to.to_s.gsub(/\D/, '')
        data = request(:post, "#{BASE_URL}/#{phone_id}/messages",
                       body: { messaging_product: 'whatsapp', to: number, type: 'template', template: })
        data.dig('messages', 0, 'id')
      end

      def templates
        url = "#{BASE_URL}/#{waba_id}/message_templates"
        query = { fields: 'name,status,id,rejected_reason,category,language,components,parameter_format', limit: 100 }
        list = []
        while url
          data = request(:get, url, query:)
          list.concat(data['data'] || [])
          url = data.dig('paging', 'next')
          query = nil
        end
        list
      end

      # Números por modelo (enviadas, entregues, lidas, cliques) da análise de modelos da Meta, somados no período.
      # A Meta aceita até 10 modelos por consulta e só responde se os insights de modelos estiverem ativos na conta.
      # Devolve { meta_id => { sent:, delivered:, read:, clicked: } }.
      def template_analytics(template_ids, from:, to:)
        totals = Hash.new { |hash, id| hash[id] = { sent: 0, delivered: 0, read: 0, clicked: 0 } }
        Array(template_ids).compact.uniq.each_slice(10) do |ids|
          url = "#{BASE_URL}/#{waba_id}/template_analytics"
          query = { start: from.to_i, end: to.to_i, granularity: 'DAILY', template_ids: ids.map(&:to_s).to_json,
                    metric_types: %w[SENT DELIVERED READ CLICKED].to_json }
          while url
            data = request(:get, url, query:)
            Array(data['data']).flat_map { |group| Array(group['data_points']) }.each do |point|
              row = totals[point['template_id'].to_s]
              row[:sent] += point['sent'].to_i
              row[:delivered] += point['delivered'].to_i
              row[:read] += point['read'].to_i
              row[:clicked] += Array(point['clicked']).sum { |click| click['count'].to_i }
            end
            url = data.dig('paging', 'next')
            query = nil
          end
        end
        totals
      end

      # Liga os insights de modelos da conta na Meta (necessário para template_analytics).
      def enable_template_insights!
        request(:post, "#{BASE_URL}/#{waba_id}", query: { is_enabled_for_insights: true })
        true
      end

      private

      def phone_id = @client.whatsapp_cloud_phone_number_id
      def waba_id = @client.whatsapp_cloud_business_account_id
      def token = @client.whatsapp_cloud_access_token

      def request(verb, url, body: nil, query: nil)
        raise NotConfigured, 'A API Oficial do WhatsApp não está configurada para este cliente.' unless configured?

        opts = { headers: { 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json' }, timeout: TIMEOUT }
        opts[:body] = body.to_json if body
        opts[:query] = query if query
        response = HTTParty.public_send(verb, url, opts)
        data = parse(response.body)
        raise_error(data['error'], response.code) if data['error'] || response.code.to_i >= 400
        data
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED => e
        raise Error, "Sem resposta da Meta (#{e.class.name.demodulize})."
      end

      def parse(body)
        JSON.parse(body.to_s.presence || '{}')
      rescue JSON::ParserError
        {}
      end

      def raise_error(error, http_code)
        error ||= {}
        code = error['code'].to_i
        message = scrub(error['error_user_msg'].presence || error['message'].presence || "Erro HTTP #{http_code} da Meta")
        klass = if RATE_LIMIT_CODES.include?(code) then RateLimited
                elsif BLOCKED_CODES.include?(code) then Blocked
                elsif PAUSE_CODES.include?(code) then Paused
                else Error
                end
        raise klass.new(message.truncate(250), code: code.zero? ? nil : code)
      end

      def scrub(message)
        token.present? ? message.to_s.gsub(token, '[token]') : message.to_s
      end
    end
  end
end
