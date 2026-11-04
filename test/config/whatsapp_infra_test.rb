require 'test_helper'
require 'erb'
require 'yaml'

class WhatsappInfraTest < ActiveSupport::TestCase
  test 'sidekiq_whatsapp.yml processa apenas a fila whatsapp' do
    config = YAML.load_file(Rails.root.join('config/sidekiq_whatsapp.yml'))
    assert_equal ['whatsapp'], config[:queues]
  end

  test 'sidekiq.yml principal nao processa a fila whatsapp' do
    refute_includes File.read(Rails.root.join('config/sidekiq.yml')), 'whatsapp'
  end

  test 'Procfile tem processo whatsapp dedicado' do
    lines = File.read(Rails.root.join('Procfile')).lines.map(&:strip)
    assert_includes lines, 'whatsapp: bundle exec sidekiq -C config/sidekiq_whatsapp.yml'
  end

  test 'storage.yml define o servico amazon em S3' do
    config = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/storage.yml'))).result, aliases: true)
    assert_equal 'S3', config.dig('amazon', 'service')
  end

  test 'storage.yml usa as variaveis do Bucketeer quando WHATSAPP_S3_* nao existem' do
    vars = { 'BUCKETEER_BUCKET_NAME' => 'bucketeer-x', 'BUCKETEER_AWS_REGION' => 'us-east-1',
             'BUCKETEER_AWS_ACCESS_KEY_ID' => 'AK', 'BUCKETEER_AWS_SECRET_ACCESS_KEY' => 'SK' }
    saved = (vars.keys + %w[WHATSAPP_S3_BUCKET WHATSAPP_S3_ACCESS_KEY_ID]).index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    ENV.delete('WHATSAPP_S3_BUCKET')
    ENV.delete('WHATSAPP_S3_ACCESS_KEY_ID')
    amazon = YAML.safe_load(ERB.new(File.read(Rails.root.join('config/storage.yml'))).result, aliases: true)['amazon']
    assert_equal 'bucketeer-x', amazon['bucket']
    assert_equal 'AK', amazon['access_key_id']
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
