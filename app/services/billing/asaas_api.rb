module Billing
  # Cliente mínimo da API v3 do Asaas. A chave fica em ASAAS_API_KEY (de
  # produção ou sandbox); ASAAS_API_URL troca a base para o sandbox.
  class AsaasApi
    DEFAULT_URL = 'https://api.asaas.com/v3'.freeze
    TIMEOUT = 15

    class Error < StandardError; end

    def self.configured?
      ENV['ASAAS_API_KEY'].present?
    end

    def initialize(api_key: ENV.fetch('ASAAS_API_KEY'), base_url: ENV.fetch('ASAAS_API_URL', DEFAULT_URL))
      @api_key = api_key
      @base_url = base_url
    end

    def find_customer(cpf_cnpj)
      get('/customers', cpfCnpj: cpf_cnpj).fetch('data', []).first
    end

    def create_customer(name:, cpf_cnpj:, email: nil)
      post('/customers', { name: name, cpfCnpj: cpf_cnpj, email: email.presence }.compact)
    end

    def find_payment(external_reference)
      get('/payments', externalReference: external_reference).fetch('data', []).find { |p| !p['deleted'] }
    end

    def create_payment(customer:, value:, due_date:, description:, external_reference:)
      post('/payments', customer: customer, billingType: 'UNDEFINED', value: value.to_f,
                        dueDate: due_date.iso8601, description: description,
                        externalReference: external_reference)
    end

    private

    def get(path, query)
      handle HTTParty.get("#{@base_url}#{path}", query: query, headers: headers, timeout: TIMEOUT)
    end

    def post(path, body)
      handle HTTParty.post("#{@base_url}#{path}", body: body.to_json, headers: headers, timeout: TIMEOUT)
    end

    def headers
      { 'access_token' => @api_key, 'Content-Type' => 'application/json', 'User-Agent' => 'mewtda-painel' }
    end

    def handle(response)
      return response.parsed_response if response.success?

      errors = Array(response.parsed_response.is_a?(Hash) ? response.parsed_response['errors'] : nil)
      message = errors.map { |e| e['description'] }.compact.join('; ').presence || "HTTP #{response.code}"
      raise Error, message
    end
  end
end
