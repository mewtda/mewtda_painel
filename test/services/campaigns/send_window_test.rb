require 'test_helper'

class SendWindowTest < ActiveSupport::TestCase
  def window = Campaigns::SendWindow.new(days: [1, 3, 4], from: '08:00', to: '12:00')

  def at(day, hour, minute = 0) = Time.zone.local(2026, 11, day, hour, minute)

  test 'open only on the chosen days and inside the hours' do
    assert window.open?(at(16, 9))
    assert window.open?(at(18, 8))
    assert_not window.open?(at(16, 12))
    assert_not window.open?(at(17, 9))
    assert_not window.open?(at(16, 7, 59))
  end

  test 'next opening is today when still before the start, otherwise the next allowed day' do
    assert_equal at(16, 8), window.next_opening(at(16, 6))
    assert_equal at(18, 8), window.next_opening(at(16, 13))
    assert_equal at(19, 8), window.next_opening(at(18, 12))
    assert_equal at(23, 8), window.next_opening(at(19, 13))
  end

  test 'next opening is now when the window is open' do
    assert_equal at(16, 9), window.next_opening(at(16, 9))
  end

  test 'summary reads like a sentence and invalid windows are rejected' do
    assert_equal 'Seg, Qua e Qui, das 08:00 às 12:00', window.summary
    assert_not Campaigns::SendWindow.new(days: [], from: '08:00', to: '12:00').valid?
    assert_not Campaigns::SendWindow.new(days: [1], from: '12:00', to: '08:00').valid?
    assert_nil Campaigns::SendWindow.new(days: [], from: '08:00', to: '12:00').next_opening
  end
end
