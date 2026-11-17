require 'test_helper'

class Insights::WeeklyConversionTest < ActiveSupport::TestCase
  Block = Struct.new(:type, :text)
  Message = Struct.new(:content, :stop_reason)

  class FakeClaude
    attr_reader :calls

    def initialize(reply)
      @reply = reply
      @calls = []
    end

    def beta = self
    def messages = self

    def create(**params)
      @calls << params
      @reply
    end
  end

  def setup
    @client = Client.create!(name: 'Loja Insight', email: "ins-#{SecureRandom.hex(4)}@example.com")
    pixel = IntegrationUser.create!(name: 'Pixel', slug: "pixel-#{SecureRandom.hex(4)}",
                                    api_secret: SecureRandom.hex(8), client: @client)
    %w[s1 s2 s3].each { |s| ShopifyEvent.create!(client: @client, integration_user: pixel, kind: 'page_viewed', session_id: s, created_at: 1.hour.ago) }
    ShopifyEvent.create!(client: @client, integration_user: pixel, kind: 'checkout_completed', session_id: 's1', created_at: 1.hour.ago)
  end

  test 'asks Claude with the week metrics and stores one insight per week' do
    claude = FakeClaude.new(Message.new([Block.new(:text, 'Conversão de 33%...')], :end_turn))

    insight = Insights::WeeklyConversion.new(@client, client_api: claude).call
    Insights::WeeklyConversion.new(@client, client_api: claude).call

    assert_equal 'Conversão de 33%...', insight.body
    assert_equal 1, claude.calls.size
    call = claude.calls.first
    assert_equal 'claude-opus-5-5', call[:model]
    assert_equal :default, call[:fallbacks]
    metrics = JSON.parse(call[:messages].first[:content])
    assert_equal 3, metrics['sessoes']
    assert_in_delta 33.33, metrics['taxa_conversao_pct']
  end

  test 'stores nothing when Claude declines' do
    claude = FakeClaude.new(Message.new([], :refusal))

    assert_nil Insights::WeeklyConversion.new(@client, client_api: claude).call
    assert_equal 0, ConversionInsight.count
  end
end
