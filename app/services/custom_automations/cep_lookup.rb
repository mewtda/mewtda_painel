module CustomAutomations
  # Consulta o CEP na BrasilAPI e, se ela falhar, no ViaCEP. Devolve
  # { 'street', 'neighborhood', 'city', 'state', 'range' } ou nil. O resultado
  # fica em cache — CEP praticamente não muda e as APIs públicas têm limite.
  #
  # Nenhuma das duas devolve o número da casa: no máximo a faixa do CEP
  # ("até 530 - lado par"), que vai em 'range'.
  class CepLookup
    TIMEOUT = 5
    CACHE_TTL = 30.days

    def self.call(zip)
      new.call(zip)
    end

    def call(zip)
      digits = zip.to_s.gsub(/\D/, '')
      return unless digits.size == 8

      Rails.cache.fetch("cep_lookup:#{digits}", expires_in: CACHE_TTL, skip_nil: true) do
        brasil_api(digits) || via_cep(digits)
      end
    end

    private

    def brasil_api(digits)
      data = get_json("https://brasilapi.com.br/api/cep/v2/#{digits}")
      return unless data && data['street'].present?

      { 'street' => data['street'], 'neighborhood' => data['neighborhood'], 'city' => data['city'],
        'state' => data['state'], 'range' => nil }
    end

    def via_cep(digits)
      data = get_json("https://viacep.com.br/ws/#{digits}/json/")
      return if data.nil? || data['erro'] || data['logradouro'].blank?

      { 'street' => data['logradouro'], 'neighborhood' => data['bairro'], 'city' => data['localidade'],
        'state' => data['uf'], 'range' => data['complemento'].presence }
    end

    def get_json(url)
      response = HTTParty.get(url, timeout: TIMEOUT)
      response.success? ? response.parsed_response : nil
    rescue StandardError => e
      Rails.logger.warn("[CepLookup] #{url}: #{e.class} #{e.message}")
      nil
    end
  end
end
