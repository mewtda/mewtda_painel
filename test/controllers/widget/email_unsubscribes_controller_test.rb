require 'test_helper'

class Widget::EmailUnsubscribesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @token = EmailSuppression.unsubscribe_token(@client, 'ana@example.com')
  end

  test 'show asks for confirmation without unsubscribing' do
    get widget_email_unsubscribe_path(token: @token)

    assert_response :success
    assert_match 'ana@example.com', response.body
    assert_not EmailSuppression.suppressed?(@client, 'ana@example.com')
  end

  test 'create adds the email to the refusal list' do
    post widget_email_unsubscribe_path(token: @token)

    assert_response :success
    assert EmailSuppression.suppressed?(@client, 'ana@example.com')
    assert_equal 'unsubscribe_link', @client.email_suppressions.last.source
  end

  test 'invalid token renders not found' do
    get widget_email_unsubscribe_path(token: 'invalido')

    assert_response :not_found
  end

  test 'legacy back in stock unsubscribe link also adds the email to the refusal list' do
    alert = @client.back_in_stock_alerts.create!(shopify_product_id: '1', shopify_variant_id: '2',
                                                 product_handle: 'vestido', email: 'bia@example.com')

    post widget_back_in_stock_unsubscribe_path(token: alert.generate_token_for(:unsubscribe))

    assert EmailSuppression.suppressed?(@client, 'bia@example.com')
    assert alert.reload.cancelled?
  end
end
