# O Heroku Redis usa TLS (rediss://) com certificado autoassinado: sem isso o
# Sidekiq recusa a conexão e nenhum job entra na fila. A conexão continua
# criptografada; só a verificação do certificado do Redis é dispensada
# (recomendação do Heroku para o Heroku Redis).
def sidekiq_redis_config(url = ENV['REDIS_URL'])
  config = { url: url }
  config[:ssl_params] = { verify_mode: OpenSSL::SSL::VERIFY_NONE } if url.to_s.start_with?('rediss://')
  config
end

Sidekiq.configure_server { |config| config.redis = sidekiq_redis_config }
Sidekiq.configure_client { |config| config.redis = sidekiq_redis_config }

schedule_file = Rails.root.join('config', 'schedule.yml')

if Sidekiq.server? && File.exist?(schedule_file)
  Sidekiq::Cron::Job.load_from_hash(YAML.load_file(schedule_file))
end
