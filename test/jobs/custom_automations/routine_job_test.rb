require 'test_helper'

class CustomAutomations::RoutineJobTest < ActiveJob::TestCase
  KIND = 'oneway_address_number_fix'.freeze

  def create_client(name, **attrs)
    Client.create!({ name: name, email: "#{name.parameterize}-#{SecureRandom.hex(4)}@example.com",
                     shopify_shop_url: "#{SecureRandom.hex(4)}.myshopify.com",
                     shopify_access_token: 'tok' }.merge(attrs))
  end

  test 'fans out one job per routine and matching client' do
    oneway = create_client('OneWay')
    create_client('Outra Loja')
    create_client('One Way', shopify_access_token: nil)

    CustomAutomations::RoutineJob.perform_now

    assert_enqueued_jobs 1, only: CustomAutomations::RoutineJob
    assert_enqueued_with(job: CustomAutomations::RoutineJob, args: [KIND, oneway.id])
  end

  test 'filters the fan-out by kind' do
    create_client('OneWay')

    CustomAutomations::RoutineJob.perform_now('outra_rotina')

    assert_no_enqueued_jobs only: CustomAutomations::RoutineJob
  end

  test 'runs the registered service for the client with its options' do
    oneway = create_client('OneWay')
    received = nil
    fake = Object.new
    fake.define_singleton_method(:call) { :done }

    CustomAutomations::OnewayAddressNumberFix.stub(:new, lambda { |client, **opts|
      received = [client, opts]
      fake
    }) do
      CustomAutomations::RoutineJob.perform_now(KIND, oneway.id)
    end

    assert_equal [oneway, { lookback_hours: 72 }], received
  end

  test 'does not run a routine for a client it is not registered for' do
    other = create_client('Outra Loja')

    ran = false
    CustomAutomations::OnewayAddressNumberFix.stub(:new, ->(*) { ran = true }) do
      CustomAutomations::RoutineJob.perform_now(KIND, other.id)
    end

    assert_not ran
  end
end
