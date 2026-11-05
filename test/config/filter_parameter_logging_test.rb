require 'test_helper'

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test 'webhook da Evolution não loga QR nem mensagens' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter('event' => 'qrcode.updated', 'data' => { 'qrcode' => { 'base64' => 'data:image/png;base64,AAA' } })
    assert_equal 'qrcode.updated', filtered['event']
    assert_equal '[FILTERED]', filtered['data']
  end
end
