require 'test_helper'

class Whatsapp::Cloud::ApiTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)
  TOKEN = 'EAAtoken-secreto-123'.freeze

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_cloud_phone_number_id: '111', whatsapp_cloud_business_account_id: '222',
                             whatsapp_cloud_access_token: TOKEN)
    @api = Whatsapp::Cloud::Api.new(@client)
  end

  def ok(json) = Response.new(200, json.to_json)
  def error(code, message = 'Falhou') = Response.new(400, { error: { code:, message: } }.to_json)

  test 'send_template posts the template to the phone number and returns the wamid' do
    seen = nil
    post = lambda do |url, opts|
      seen = { url:, opts: }
      ok(messages: [{ id: 'wamid.ABC' }])
    end
    id = HTTParty.stub(:post, post) do
      @api.send_template(to: '(16) 99237-5432', name: 'black_1', language: 'pt_BR', body_params: ['Ana'])
    end

    assert_equal 'wamid.ABC', id
    assert_equal 'https://graph.facebook.com/v26.0/111/messages', seen[:url]
    assert_equal "Bearer #{TOKEN}", seen[:opts][:headers]['Authorization']
    assert_equal 15, seen[:opts][:timeout]
    body = JSON.parse(seen[:opts][:body])
    assert_equal({ 'messaging_product' => 'whatsapp', 'to' => '5516992375432', 'type' => 'template',
                   'template' => { 'name' => 'black_1', 'language' => { 'code' => 'pt_BR' },
                                   'components' => [{ 'type' => 'body',
                                                      'parameters' => [{ 'type' => 'text', 'text' => 'Ana' }] }] } },
                 body)
  end

  test 'send_template without params sends no components' do
    seen = nil
    HTTParty.stub(:post, ->(_url, opts) { seen = JSON.parse(opts[:body]) and ok(messages: [{ id: 'w' }]) }) do
      @api.send_template(to: '+5516992375432', name: 'oi', language: 'pt_BR')
    end
    assert_nil seen['template']['components']
  end

  test 'maps Meta errors to exception classes without leaking the token' do
    HTTParty.stub(:post, ->(*) { error(130_429) }) do
      assert_raises(Whatsapp::Cloud::Api::RateLimited) { @api.send_template(to: '16992375432', name: 'a', language: 'pt_BR') }
    end
    HTTParty.stub(:post, ->(*) { error(131_050) }) do
      assert_raises(Whatsapp::Cloud::Api::Blocked) { @api.send_template(to: '16992375432', name: 'a', language: 'pt_BR') }
    end
    HTTParty.stub(:post, ->(*) { error(100, "Invalid token #{TOKEN}") }) do
      err = assert_raises(Whatsapp::Cloud::Api::Error) { @api.send_template(to: '16992375432', name: 'a', language: 'pt_BR') }
      assert_equal 100, err.code
      refute_includes err.message, TOKEN
    end
  end

  test 'templates follows paging.next' do
    pages = {
      'https://graph.facebook.com/v26.0/222/message_templates' =>
        ok(data: [{ name: 'a', status: 'APPROVED' }], paging: { next: 'https://graph.facebook.com/next-page' }),
      'https://graph.facebook.com/next-page' => ok(data: [{ name: 'b', status: 'PENDING' }])
    }
    list = HTTParty.stub(:get, ->(url, _opts) { pages.fetch(url) }) { @api.templates }
    assert_equal %w[a b], list.map { |t| t['name'] }
  end

  test 'create_template posts to the WABA and delete_template deletes by name' do
    seen = nil
    created = HTTParty.stub(:post, ->(url, opts) { seen = [url, JSON.parse(opts[:body])] and ok(id: '9', status: 'PENDING', category: 'MARKETING') }) do
      @api.create_template(name: 'x', category: 'MARKETING')
    end
    assert_equal 'https://graph.facebook.com/v26.0/222/message_templates', seen[0]
    assert_equal 'x', seen[1]['name']
    assert_equal '9', created['id']

    deleted = nil
    assert(HTTParty.stub(:delete, ->(url, opts) { deleted = [url, opts[:query]] and ok(success: true) }) { @api.delete_template(name: 'x') })
    assert_equal ['https://graph.facebook.com/v26.0/222/message_templates', { name: 'x' }], deleted
  end

  test 'configured? requires phone id, waba and token' do
    assert @api.configured?
    @client.whatsapp_cloud_business_account_id = nil
    refute Whatsapp::Cloud::Api.new(@client).configured?
    assert_raises(Whatsapp::Cloud::Api::NotConfigured) { Whatsapp::Cloud::Api.new(@client).templates }
  end
end
