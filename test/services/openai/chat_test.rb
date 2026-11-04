require 'test_helper'

class Openai::ChatTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body)

  # Net::HTTP dublado: captura a requisição e nunca toca a rede.
  def stub_http(response)
    captured = {}
    http = Object.new
    http.define_singleton_method(:request) { |req| captured[:request] = req; response }
    start = lambda do |host, port, **opts, &block|
      captured.merge!(host: host, port: port, opts: opts)
      block.call(http)
    end
    Net::HTTP.stub(:start, start) { yield }
    captured
  end

  test 'monta o header Bearer e devolve o conteúdo da primeira escolha' do
    body = { choices: [{ message: { role: 'assistant', content: 'Olá!' } }] }.to_json
    result = nil
    captured = stub_http(FakeResponse.new('200', body)) do
      result = Openai::Chat.new(api_key: 'sk-teste', model: 'gpt-x').reply(messages: [{ role: 'user', content: 'oi' }])
    end

    assert_equal 'Olá!', result
    assert_equal 'api.openai.com', captured[:host]
    assert_equal 'Bearer sk-teste', captured[:request]['Authorization']
    assert_equal '/v1/chat/completions', captured[:request].path
    payload = JSON.parse(captured[:request].body)
    assert_equal 'gpt-x', payload['model']
    assert_equal [{ 'role' => 'user', 'content' => 'oi' }], payload['messages']
    assert_equal 5, captured[:opts][:open_timeout]
    assert_equal 30, captured[:opts][:read_timeout]
  end

  test 'resposta não 2xx levanta Error sem vazar chave nem corpo' do
    error = nil
    stub_http(FakeResponse.new('401', '{"error":"segredo-do-corpo"}')) do
      error = assert_raises(Openai::Chat::Error) { Openai::Chat.new(api_key: 'sk-teste', model: 'm').reply(messages: []) }
    end
    refute_includes error.message, 'sk-teste'
    refute_includes error.message, 'segredo-do-corpo'
  end

  test 'resposta sem conteúdo levanta Error' do
    stub_http(FakeResponse.new('200', '{"choices":[]}')) do
      assert_raises(Openai::Chat::Error) { Openai::Chat.new(api_key: 'k', model: 'm').reply(messages: []) }
    end
  end
end
