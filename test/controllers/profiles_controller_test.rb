require 'test_helper'

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }
    sign_in User.create!(name: 'Chefe', email: "a-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                         password_confirmation: 'password123', profile_id: Profile::ADMIN)
  end

  test 'the form follows the shared form page pattern' do
    get new_profile_path

    assert_response :success
    assert_select '.users-form-page .users-form-page__header'
    assert_select '.users-form-page__footer a', text: /Voltar/
    assert_select '.profiles-form-page', count: 0
  end

  test 'invalid profile shows the errors block' do
    post profiles_path, params: { profile: { name: '' } }

    assert_response :success
    assert_select '.users-form-page__errors li'
  end
end
