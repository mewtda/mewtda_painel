require 'test_helper'

class Widget::BackInStockControllerTest < ActionDispatch::IntegrationTest
  include BackInStockHelper

  setup do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com", site_url: 'https://loja.com')
    @setting = BackInStockSetting.create!(client:)
  end

  test 'config is public and cached for a few minutes so the button shows up faster' do
    get widget_back_in_stock_config_path(token: @setting.public_token)

    assert_response :success
    assert_equal @setting.button_text, response.parsed_body['button_text']
    assert_match 'public', response.headers['Cache-Control']
    assert_match 'max-age=300', response.headers['Cache-Control']
  end

  test 'unknown token is not found' do
    get widget_back_in_stock_config_path(token: 'nope')
    assert_response :not_found
  end

  test 'install snippet loads the widget with async (fetches start without waiting for the whole page)' do
    snippet = back_in_stock_snippet(@setting)
    assert_match ' async></script>', snippet
    assert_no_match 'defer', snippet
  end

  def post_alert(variant_id: 101, check: :ok)
    params = { token: @setting.public_token, elapsed_ms: 5000,
               alert: { shopify_product_id: 10, shopify_variant_id: variant_id, product_handle: 'vestido',
                        product_title: 'Vestido', email: "ana-#{SecureRandom.hex(3)}@example.com" } }
    checker = Object.new
    checker.define_singleton_method(:call) { |**| check }
    BackInStock::VariantCheck.stub(:new, ->(*) { checker }) do
      post widget_back_in_stock_alerts_path, params:, as: :json, headers: { 'Origin' => 'https://loja.com' }
    end
  end

  test 'registers an alert for a product that exists in the store' do
    assert_difference -> { BackInStockAlert.count }, 1 do
      post_alert
    end
    assert_response :created
  end

  test 'refuses an alert for a product or variant the store does not have' do
    assert_no_difference -> { BackInStockAlert.count } do
      post_alert(check: :unknown)
    end
    assert_response :unprocessable_entity
  end

  test 'keeps the alert when the store did not answer (real customer is not lost)' do
    assert_difference -> { BackInStockAlert.count }, 1 do
      post_alert(check: :error)
    end
    assert_response :created
  end

  test 'refuses while Shopify is throttling lookups (abnormal volume)' do
    assert_no_difference -> { BackInStockAlert.count } do
      post_alert(check: :throttled)
    end
    assert_response :too_many_requests
  end

  test 'stops accepting new alerts after the daily limit for the store' do
    BackInStockAlert.stub(:daily_limit_reached?, true) do
      assert_no_difference -> { BackInStockAlert.count } do
        post_alert
      end
    end
    assert_response :too_many_requests
  end
end
