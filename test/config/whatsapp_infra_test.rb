require 'test_helper'
require 'erb'
require 'yaml'

class WhatsappInfraTest < ActiveSupport::TestCase
  test 'não existe mais processo nem fila da Evolution' do
    refute File.exist?(Rails.root.join('config/sidekiq_whatsapp.yml'))
    refute_includes File.read(Rails.root.join('Procfile')), 'whatsapp'
    refute_includes File.read(Rails.root.join('config/sidekiq.yml')), 'whatsapp'
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
