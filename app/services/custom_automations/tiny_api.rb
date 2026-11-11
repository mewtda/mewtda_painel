module CustomAutomations
  # Cliente mínimo da API v2 do Tiny (https://tiny.com.br/api-docs/api2), uma
  # instância por token/conta. Respeita o limite de requisições do Tiny: espera
  # um pouco entre chamadas e, se a API responder "bloqueada" (código 6), dá um
  # tempo e tenta de novo antes de desistir.
  class TinyApi
    BASE_URL = 'https://api.tiny.com.br/api2'.freeze
    NO_RECORDS = '20'.freeze
    RATE_LIMITED = '6'.freeze
    MAX_RATE_LIMIT_RETRIES = 3
    INVOICE_TIMEOUT = 600

    class Error < StandardError; end

    def initialize(token, throttle: 1.0, rate_limit_wait: 60)
      raise ArgumentError, 'Token do Tiny não configurado' if token.blank?

      @token = token
      @throttle = throttle
      @rate_limit_wait = rate_limit_wait
    end

    # Dados da empresa dona da conta (razão social, CNPJ, IE, endereço).
    def account_info
      call('info.php')['conta']
    end

    # Procura um produto pelo código (SKU) exato — a pesquisa do Tiny é por
    # "contém", então filtra o resultado pelo código idêntico. Ignora produtos
    # pai (tipoVariacao "P"): eles não podem ir numa nota, e na matriz da
    # Fernanda Farah há pais com o mesmo código de variações reais.
    def find_product_by_code(code)
      result = call('produtos.pesquisa.php', pesquisa: code, allow_empty: true)
      match = Array(result['produtos']).map { |p| p['produto'] }
                                       .find { |p| p['codigo'].to_s == code.to_s && p['tipoVariacao'] != 'P' }
      match && product(match['id'])
    end

    def product(id)
      call('produto.obter.php', id: id)['produto']
    end

    # Inclui a nota sem emitir — fica como "pendente" no Tiny até chamar emit_invoice.
    def create_invoice(payload)
      # Nota com centenas de itens: o Tiny leva bem mais de 60s pra responder e,
      # se a gente desistir antes, ele cria a nota mesmo assim (fica órfã).
      result = call('nota.fiscal.incluir.php', timeout: INVOICE_TIMEOUT, nota: payload.to_json)
      registro = records(result).first || {}
      raise Error, format_errors(registro['erros']) if registro['status'] != 'OK'

      registro
    end

    def emit_invoice(id)
      call('nota.fiscal.emitir.php', id: id, enviarEmail: 'N')
    end

    private

    def call(endpoint, allow_empty: false, timeout: 60, **params)
      attempts = 0

      loop do
        sleep(@throttle) if @throttle.positive?
        response = HTTParty.post("#{BASE_URL}/#{endpoint}",
                                 body: params.merge(token: @token, formato: 'json'),
                                 timeout: timeout)
        retorno = JSON.parse(response.body)['retorno'] || {}

        return retorno if retorno['status'] == 'OK'
        return {} if allow_empty && retorno['codigo_erro'].to_s == NO_RECORDS

        if retorno['codigo_erro'].to_s == RATE_LIMITED && attempts < MAX_RATE_LIMIT_RETRIES
          attempts += 1
          sleep(@rate_limit_wait)
          next
        end

        # Na inclusão de nota os erros de validação vêm dentro de cada registro.
        record_errors = records(retorno).flat_map { |r| Array(r['erros']) }
        raise Error, "Tiny #{endpoint}: #{format_errors(Array(retorno['erros']) + record_errors)}"
      end
    rescue JSON::ParserError
      raise Error, "Tiny #{endpoint}: resposta inválida"
    end

    # Com um registro só, o Tiny devolve "registros" como objeto
    # ({"registro" => {...}}), e não como lista ([{"registro" => {...}}]).
    def records(retorno)
      registros = retorno['registros']
      registros = [registros] if registros.is_a?(Hash)
      Array(registros).filter_map { |r| r.is_a?(Hash) ? (r['registro'] || r) : nil }
    end

    def format_errors(erros)
      messages = Array(erros).map { |e| e.is_a?(Hash) ? e['erro'] : e }.compact
      messages.presence&.join('; ') || 'erro desconhecido'
    end
  end
end
