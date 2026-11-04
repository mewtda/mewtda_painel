require 'net/http'
require 'json'

module Openai
  # Chat Completions da OpenAI. Sem retries; nunca registra a chave nem o corpo da resposta.
  class Chat
    class Error < StandardError; end

    URL = URI('https://api.openai.com/v1/chat/completions').freeze

    def initialize(api_key:, model:)
      @api_key = api_key
      @model = model
    end

    def reply(messages:)
      request = Net::HTTP::Post.new(URL.request_uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = { model: @model, messages: messages }.to_json

      response = Net::HTTP.start(URL.host, URL.port, use_ssl: true, open_timeout: 5, read_timeout: 30,
                                                     max_retries: 0) { |http| http.request(request) }
      raise Error, "OpenAI HTTP #{response.code}" unless response.code.to_s.start_with?('2')

      content = JSON.parse(response.body).dig('choices', 0, 'message', 'content')
      raise Error, 'OpenAI sem conteúdo' if content.blank?

      content
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError => e
      raise Error, "OpenAI #{e.class.name}"
    end
  end
end
