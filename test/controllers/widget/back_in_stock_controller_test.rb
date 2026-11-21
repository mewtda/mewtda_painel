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
end
