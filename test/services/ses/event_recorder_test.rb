require 'test_helper'

class Ses::EventRecorderTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sent')
    @recipient = @campaign.recipients.create!(email: 'ana@example.com', status: 'sent', sent_at: Time.current)
  end

  def payload(type, extra = {}, tags = nil)
    tags ||= { 'source' => ['campaign'], 'client_id' => [@client.id.to_s], 'campaign_id' => [@campaign.id.to_s],
               'recipient_id' => [@recipient.id.to_s] }
    { 'eventType' => type, 'mail' => { 'messageId' => 'msg-1', 'timestamp' => '2026-11-14T10:00:00.000Z', 'tags' => tags,
                                       'destination' => ['ana@example.com'] } }.merge(extra)
  end

  def record(data) = Ses::EventRecorder.new(data).call

  test 'stores a delivery tied to the campaign recipient' do
    event = record(payload('Delivery', 'delivery' => { 'timestamp' => '2026-11-14T10:00:05.000Z' }))

    assert_equal [@client, @campaign, @recipient, 'delivery', 'campaign'],
                 [event.client, event.campaign, event.campaign_recipient, event.event_type, event.source]
    assert_equal Time.utc(2026, 11, 14, 10, 0, 5), event.occurred_at
  end

  test 'stores the clicked link' do
    event = record(payload('Click', 'click' => { 'link' => 'https://loja.com/p', 'timestamp' => '2026-11-14T11:00:00.000Z' }))

    assert_equal 'https://loja.com/p', event.link
  end

  test 'ignores a repeated event' do
    data = payload('Open', 'open' => { 'timestamp' => '2026-11-14T11:00:00.000Z' })
    record(data)

    assert_no_difference('EmailEvent.count') { assert_nil record(data) }
  end

  test 'a permanent bounce puts the address on the refusal list' do
    record(payload('Bounce', 'bounce' => { 'bounceType' => 'Permanent', 'timestamp' => '2026-11-14T10:00:05.000Z',
                                           'bouncedRecipients' => [{ 'emailAddress' => 'Ana@Example.com' }] }))

    suppression = EmailSuppression.find_by!(client: @client, email: 'ana@example.com')
    assert_equal 'bounce', suppression.source
    assert_equal 'permanent', EmailEvent.last.bounce_type
  end

  test 'a transient bounce does not suppress the address' do
    record(payload('Bounce', 'bounce' => { 'bounceType' => 'Transient', 'timestamp' => '2026-11-14T10:00:05.000Z',
                                           'bouncedRecipients' => [{ 'emailAddress' => 'ana@example.com' }] }))

    assert_not EmailSuppression.suppressed?(@client, 'ana@example.com')
    assert_equal 1, EmailEvent.where(event_type: 'bounce').count
  end

  test 'a complaint puts the address on the refusal list' do
    record(payload('Complaint', 'complaint' => { 'timestamp' => '2026-11-14T10:00:05.000Z',
                                                 'complainedRecipients' => [{ 'emailAddress' => 'ana@example.com' }] }))

    assert_equal 'complaint', EmailSuppression.find_by!(client: @client, email: 'ana@example.com').source
  end

  test 'ties back in stock events to the alert' do
    alert = BackInStockAlert.create!(client: @client, shopify_product_id: 1, shopify_variant_id: 2, product_handle: 'tenis',
                                     email: 'ana@example.com', consented_at: Time.current)
    tags = { 'source' => ['back_in_stock'], 'client_id' => [@client.id.to_s], 'alert_id' => [alert.id.to_s] }

    event = record(payload('Delivery', { 'delivery' => { 'timestamp' => '2026-11-14T10:00:05.000Z' } }, tags))

    assert_equal [alert, 'back_in_stock', nil], [event.back_in_stock_alert, event.source, event.campaign_id]
  end

  test 'ignores events without our tags, from other stores or with an unknown type' do
    assert_nil record(payload('Delivery', {}, {}))
    assert_nil record(payload('Delivery', {}, { 'source' => ['campaign'], 'client_id' => ['0'], 'campaign_id' => ['1'] }))
    other = Client.create!(name: 'Outra', email: "outra-#{SecureRandom.hex(4)}@example.com")
    foreign = { 'source' => ['campaign'], 'client_id' => [other.id.to_s], 'campaign_id' => [@campaign.id.to_s] }
    assert_nil record(payload('Delivery', {}, foreign))
    assert_nil record(payload('DeliveryDelay'))
    assert_equal 0, EmailEvent.count
  end
end
