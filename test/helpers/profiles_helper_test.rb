require 'test_helper'

class ProfilesHelperTest < ActionView::TestCase
  test 'each known profile has its own icon and others get a generic badge' do
    admin = Profile.new(id: Profile::ADMIN)
    custom = Profile.new(id: 999)

    assert_includes profile_icon(admin), 'fa-user-shield'
    assert_includes profile_icon(Profile.new(id: Profile::AFFILIATE)), 'fa-handshake'
    assert_includes profile_icon(custom), 'fa-id-badge'
  end
end
