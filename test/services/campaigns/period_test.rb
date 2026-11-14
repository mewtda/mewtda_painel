require 'test_helper'

class Campaigns::PeriodTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 11, 14)

  def period(key = nil, from = nil, to = nil) = Campaigns::Period.new(key, from, to, today: TODAY)

  test 'defaults to the last 30 days' do
    assert_equal '30d', period.key
    assert_equal [Date.new(2026, 10, 16), TODAY], [period.from, period.to]
  end

  test 'presets cover the expected ranges' do
    assert_equal Date.new(2026, 11, 8), period('7d').from
    assert_equal Date.new(2026, 11, 1), period('month').from
    assert_equal Date.new(2025, 11, 15), period('12m').from
    assert_nil period('all').from
    assert_equal 'Desde o início', period('all').label
  end

  test 'custom range swaps reversed dates and formats the label' do
    custom = period('custom', '2026-11-10', '2026-11-01')

    assert_equal 'custom', custom.key
    assert_equal [Date.new(2026, 11, 1), Date.new(2026, 11, 10)], [custom.from, custom.to]
    assert_equal '01/11/2026 - 10/11/2026', custom.label
  end

  test 'invalid custom dates and unknown keys fall back to the default' do
    assert_equal '30d', period('custom', 'abc', '2026-11-10').key
    assert_equal '30d', period('custom', nil, nil).key
    assert_equal '30d', period('forever').key
  end

  test 'time range spans the whole first and last day' do
    range = period('custom', '2026-11-01', '2026-11-02').time_range

    assert_equal Time.zone.local(2026, 11, 1).beginning_of_day, range.begin
    assert_equal Time.zone.local(2026, 11, 2).end_of_day, range.end
  end
end
