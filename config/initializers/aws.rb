if ENV['AWS_SES_ACCESS_KEY_ID'].present?
  Aws.config.update(
    region: ENV.fetch('AWS_SES_REGION', 'us-east-1'),
    credentials: Aws::Credentials.new(ENV['AWS_SES_ACCESS_KEY_ID'], ENV['AWS_SES_SECRET_ACCESS_KEY'])
  )
end
