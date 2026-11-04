require 'test_helper'

class SendCartRecoveryNotificationJobTest < ActiveJob::TestCase
  def setup
    @client = Client.create!(name: 'Loja', email: "l-#{SecureRandom.hex(4)}@example.com")
    @campaign = @client.campaigns.create!(
      name: 'Recuperação', kind: 'cart_recovery', message: 'Oi {nome}', resend_message: 'Volta',
      start_date: Date.current - 1.day, end_date: Date.current + 1.year, send_delay_minutes: 60
    )
    @checkout = @client.abandoned_checkouts.create!(shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999',
                                                    checkout_created_at: 2.hours.ago, recovery_url: 'http://x')
  end

  def with_zapi_stub(response)
    calls = []
    fake = Object.new
    fake.define_singleton_method(:send_text) { |**kw| calls << kw; response }
    original = Zapi::Client.method(:new)
    Zapi::Client.define_singleton_method(:new) { |*_| fake }
    yield calls
  ensure
    Zapi::Client.define_singleton_method(:new, original)
  end

  def link(name)
    conn = @client.whatsapp_connections.create!(name: name, state: 'connected')
    Whatsapp::CampaignConnection.create!(campaign: @campaign, connection: conn)
    conn
  end

  test 'zapi first message records the provider and marks sent' do
    with_zapi_stub({ 'zaapId' => 'z' }) do |calls|
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi {nome}', nil, 'first')
      assert_equal 1, calls.size
    end
    @checkout.reload
    assert_equal 'zapi', @checkout.whatsapp_provider
    assert_nil @checkout.whatsapp_connection_id
    assert_equal 'Oi cliente', @checkout.first_message_sent
    assert_not_nil @checkout.first_notified_at
  end

  test 'zapi failure does not record the message as sent' do
    with_zapi_stub(nil) do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi', nil, 'first')
    end
    assert_nil @checkout.reload.first_message_sent
  end

  test 'evolution first message queues through the connection and stores the channel' do
    @client.update!(whatsapp_provider: 'evolution')
    conn = link('A')

    assert_difference 'Whatsapp::Message.count', 1 do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi {nome}', nil, 'first')
    end
    @checkout.reload
    assert_equal 'evolution', @checkout.whatsapp_provider
    assert_equal conn.id, @checkout.whatsapp_connection_id
    assert_equal Whatsapp::Message.last.conversation_id, @checkout.whatsapp_conversation_id
    assert_equal 'Oi cliente', @checkout.first_message_sent
  end

  test 'evolution second message goes through the same connection as the first' do
    @client.update!(whatsapp_provider: 'evolution')
    a = link('A')
    b = link('B')
    # rodízio apontaria A (nunca usada); a 1ª saiu por B
    @campaign.whatsapp_campaign_connections.find_by(connection: b).update!(last_assigned_at: 1.hour.ago)
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'evolution', whatsapp_connection_id: b.id)

    SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')

    assert_equal b.id, Whatsapp::Message.last.connection_id
    assert_not_equal a.id, Whatsapp::Message.last.connection_id
    assert_equal 'Volta', @checkout.reload.second_message_sent
  end

  test 'second message is skipped when the first went by zapi and the client is now evolution' do
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'zapi')
    @client.update!(whatsapp_provider: 'evolution')
    link('A')

    assert_no_difference 'Whatsapp::Message.count' do
      with_zapi_stub({ 'zaapId' => 'z' }) do |calls|
        SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')
        assert_empty calls
      end
    end
    @checkout.reload
    assert_not_nil @checkout.second_notified_at
    assert_nil @checkout.second_message_sent
    assert_equal 'canal da 1ª mensagem indisponível', @checkout.skip_reason
    assert_equal :skipped, @checkout.status
  end

  test 'second message waits while the first connection is disconnected and goes out once it is back' do
    @client.update!(whatsapp_provider: 'evolution')
    a = link('A')
    link('B')
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'evolution', whatsapp_connection_id: a.id)
    a.update!(state: 'disconnected')

    assert_no_difference 'Whatsapp::Message.count' do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')
    end
    @checkout.reload
    assert_nil @checkout.second_notified_at
    assert_nil @checkout.skip_reason

    a.update!(state: 'connected')
    SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')
    assert_equal a.id, Whatsapp::Message.last.connection_id
    assert_equal 'Volta', @checkout.reload.second_message_sent
  end

  test 'second message is skipped when the first connection left the campaign' do
    @client.update!(whatsapp_provider: 'evolution')
    link('A')
    other = @client.whatsapp_connections.create!(name: 'Fora', state: 'connected')
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'evolution', whatsapp_connection_id: other.id)

    assert_no_difference 'Whatsapp::Message.count' do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')
    end
    assert_equal :skipped, @checkout.reload.status
  end

  test 'second message is skipped when the connection was deleted' do
    @client.update!(whatsapp_provider: 'evolution')
    link('A')
    gone = @client.whatsapp_connections.create!(name: 'X', state: 'connected')
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'evolution', whatsapp_connection_id: gone.id)
    gone.destroy!

    assert_nil @checkout.reload.whatsapp_connection_id
    assert_no_difference 'Whatsapp::Message.count' do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')
    end
    assert_equal :skipped, @checkout.reload.status
  end

  test 'evolution with no connected number leaves the checkout pending' do
    @client.update!(whatsapp_provider: 'evolution')
    @client.whatsapp_connections.create!(name: 'A', state: 'disconnected')

    SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi', nil, 'first')

    @checkout.reload
    assert_nil @checkout.first_notified_at
    assert_equal :pending, @checkout.status
  end
end
