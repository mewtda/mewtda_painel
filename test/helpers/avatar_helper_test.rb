require 'test_helper'

class AvatarHelperTest < ActionView::TestCase
  test 'initials use the first letters of the first two names' do
    assert_equal 'MF', avatar_initials('Maria Fernanda Kac')
    assert_equal 'M', avatar_initials('Maria Fernanda', count: 1)
    assert_equal 'A', avatar_initials('ana')
    assert_equal '?', avatar_initials(nil)
    assert_equal '?', avatar_initials('  ')
  end

  test 'the tone is stable per name, ignoring case and spaces' do
    assert_equal avatar_tone('Maria Kac'), avatar_tone('  maria kac ')
    assert_includes (0...AvatarHelper::AVATAR_TONES).to_a, avatar_tone('Qualquer Nome')
  end

  test 'different names spread across several tones' do
    names = %w[Ana Bia Carla Duda Eva Flavia Gabi Helena Iris Julia Karen Lais Mila Nina Olga Paula]

    assert_operator names.map { |name| avatar_tone(name) }.uniq.size, :>=, 4
  end

  test 'avatar_tag renders the initials with the tone class' do
    html = avatar_tag('Maria Kac', class: 'customers-avatar')

    assert_includes html, ">MK<"
    assert_includes html, "avatar avatar--tone-#{avatar_tone('Maria Kac')} customers-avatar"
  end
end
