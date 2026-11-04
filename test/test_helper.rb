ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

# dotenv carrega o .env do desenvolvedor (que aponta para produção): testes nunca podem alcançar serviços reais.
%w[EVOLUTION_API_URL EVOLUTION_API_KEY WHATSAPP_WEBHOOK_BASE_URL].each { |k| ENV.delete(k) }
ENV.keys.grep(/\AOPENAI_/).each { |k| ENV.delete(k) }
require 'minitest/mock' # habilita Object#stub, usado para dublar Shopify::Client/CreateCustomer nos testes

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
