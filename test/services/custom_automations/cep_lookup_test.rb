require 'test_helper'

class CustomAutomations::CepLookupTest < ActiveSupport::TestCase
  Response = Struct.new(:success?, :parsed_response)

  def stub_get(responses, &)
    calls = []
    HTTParty.stub(:get, lambda { |url, **|
      calls << url
      responses.fetch(url[%r{brasilapi|viacep}])
    }, &)
    calls
  end

  test 'uses BrasilAPI when it answers' do
    result = nil
    calls = stub_get('brasilapi' => Response.new(true, { 'street' => 'Rua Pedroso Alvarenga',
                                                          'neighborhood' => 'Itaim Bibi',
                                                          'city' => 'São Paulo', 'state' => 'SP' })) do
      result = CustomAutomations::CepLookup.call('04531-000')
    end

    assert_equal 'Rua Pedroso Alvarenga', result['street']
    assert_equal 'São Paulo', result['city']
    assert_equal ['https://brasilapi.com.br/api/cep/v2/04531000'], calls
  end

  test 'falls back to ViaCEP' do
    result = nil
    stub_get('brasilapi' => Response.new(false, nil),
             'viacep' => Response.new(true, { 'logradouro' => 'Rua Pedroso Alvarenga', 'bairro' => 'Itaim Bibi',
                                              'localidade' => 'São Paulo', 'uf' => 'SP',
                                              'complemento' => 'até 530 - lado par' })) do
      result = CustomAutomations::CepLookup.call('04531000')
    end

    assert_equal 'Rua Pedroso Alvarenga', result['street']
    assert_equal 'até 530 - lado par', result['range']
  end

  test 'ignores invalid CEPs without calling the APIs' do
    calls = stub_get({}) { assert_nil CustomAutomations::CepLookup.call('123') }

    assert_empty calls
  end
end
