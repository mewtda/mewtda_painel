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
end
