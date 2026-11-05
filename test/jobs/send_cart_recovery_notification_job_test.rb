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

  def link(name)
    conn = @client.whatsapp_connections.create!(name: name, state: 'connected')
    Whatsapp::CampaignConnection.create!(campaign: @campaign, connection: conn)
    conn
  end

  test 'evolution first message queues through the connection and stores the channel' do
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

  test 'second message is skipped when the first went by the removed Z-API' do
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'zapi')
    link('A')

    assert_no_difference 'Whatsapp::Message.count' do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')
    end
    @checkout.reload
    assert_not_nil @checkout.second_notified_at
    assert_nil @checkout.second_message_sent
    assert_equal 'canal da 1ª mensagem indisponível', @checkout.skip_reason
    assert_equal :skipped, @checkout.status
  end

  test 'second message waits while the first connection is disconnected and goes out once it is back' do
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
    link('A')
    other = @client.whatsapp_connections.create!(name: 'Fora', state: 'connected')
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'evolution', whatsapp_connection_id: other.id)

    assert_no_difference 'Whatsapp::Message.count' do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second')
    end
    assert_equal :skipped, @checkout.reload.status
  end

  test 'second message is skipped when the connection was deleted' do
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
    @client.whatsapp_connections.create!(name: 'A', state: 'disconnected')

    SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi', nil, 'first')

    @checkout.reload
    assert_nil @checkout.first_notified_at
    assert_equal :pending, @checkout.status
  end

  test 'two automatic first jobs for the same checkout send exactly once' do
    link('A')
    assert_difference 'Whatsapp::Message.count', 1 do
      2.times { SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi', nil, 'first') }
    end
  end

  test 'two automatic second jobs for the same checkout send exactly once' do
    a = link('A')
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'evolution', whatsapp_connection_id: a.id)
    assert_difference 'Whatsapp::Message.count', 1 do
      2.times { SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Volta', nil, 'second') }
    end
  end

  test 'manual resend after the first was sent sends again through the same channel' do
    a = link('A')
    link('B')
    SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi', nil, 'first')
    first = Whatsapp::Message.last.connection_id
    assert_difference 'Whatsapp::Message.count', 1 do
      SendCartRecoveryNotificationJob.perform_now(@checkout.id, 'Oi', nil, 'first', true)
    end
    assert_equal first, Whatsapp::Message.last.connection_id
      end

  test 'channel_available? is false when the first message channel is gone' do
    link('A')
    @checkout.update!(first_notified_at: 1.day.ago, whatsapp_provider: 'zapi')
    assert_not SendCartRecoveryNotificationJob.channel_available?(@checkout, @client, @campaign)
  end
end
