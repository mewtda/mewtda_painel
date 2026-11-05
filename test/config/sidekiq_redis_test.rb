require 'test_helper'

class SidekiqRedisTest < ActiveSupport::TestCase
  test 'rediss do Heroku aceita o certificado autoassinado' do
    config = sidekiq_redis_config('rediss://:x@host:24810')
    assert_equal OpenSSL::SSL::VERIFY_NONE, config.dig(:ssl_params, :verify_mode)
  end

  test 'redis sem TLS não recebe ssl_params' do
    assert_nil sidekiq_redis_config('redis://localhost:6379/1')[:ssl_params]
  end

  test 'cable.yml de produção aceita o certificado do Heroku Redis' do
    cable = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/cable.yml'))).result, aliases: true)
    assert_equal OpenSSL::SSL::VERIFY_NONE, cable.dig('production', 'ssl_params', 'verify_mode')
  end
end
