require 'test_helper'

class EmailSuppressionTest < ActiveSupport::TestCase
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_alert(client, email)
    client.back_in_stock_alerts.create!(shopify_product_id: '1', shopify_variant_id: SecureRandom.hex(3),
                                        product_handle: 'vestido', email:)
  end

  test 'unsubscribe! is idempotent and normalizes the email' do
    client = build_client

    assert_difference 'EmailSuppression.count', 1 do
      EmailSuppression.unsubscribe!(client, ' Ana@Example.COM ')
      EmailSuppression.unsubscribe!(client, 'ana@example.com')
    end

    assert EmailSuppression.suppressed?(client, 'ANA@example.com')
    assert_not EmailSuppression.suppressed?(build_client, 'ana@example.com')
  end

  test 'unsubscribe! cancels pending back in stock alerts of that email' do
    client = build_client
    alert = build_alert(client, 'ana@example.com')
    other = build_alert(client, 'bia@example.com')

    EmailSuppression.unsubscribe!(client, 'ana@example.com')

    assert alert.reload.cancelled?
    assert other.reload.pending?
  end

  test 'unsubscribe tokens round-trip and reject tampering' do
    client = build_client
    token = EmailSuppression.unsubscribe_token(client, 'Ana@example.com')

    assert_equal [client, 'ana@example.com'], EmailSuppression.resolve_token(token)
    assert_nil EmailSuppression.resolve_token("#{token}x")
    assert_nil EmailSuppression.resolve_token(nil)
    assert_no_match %r{[/+=]}, token
  end

  test 'rejects duplicates and invalid emails' do
    client = build_client
    EmailSuppression.create!(client:, email: 'ana@example.com', source: 'manual')

    assert_not EmailSuppression.new(client:, email: 'ANA@example.com', source: 'manual').valid?
    assert_not EmailSuppression.new(client:, email: 'nao-e-email', source: 'manual').valid?
  end
end
