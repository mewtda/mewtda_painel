require 'test_helper'

class PhoneHelperTest < ActionView::TestCase
  test 'formats Brazilian mobile and landline numbers' do
    assert_equal '(31) 99425-0086', format_phone('+5531994250086')
    assert_equal '(31) 99425-0086', format_phone('5531994250086')
    assert_equal '(11) 98765-4321', format_phone('11987654321')
    assert_equal '(11) 3456-7890', format_phone('+551134567890')
  end

  test 'keeps unknown formats untouched and shows a dash when blank' do
    assert_equal '+14079894053', format_phone('+14079894053')
    assert_equal '—', format_phone(nil)
    assert_equal '—', format_phone('')
  end
end
