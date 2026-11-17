require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  def build_user(admin: false, name: 'Pessoa')
    profile_id = admin ? Profile::ADMIN : Profile::USER
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = admin ? 'Admin' : 'User' }
    User.create!(name:, email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                 password_confirmation: 'password123', profile_id:)
  end

  setup do
    @admin = build_user(admin: true, name: 'Chefe')
    sign_in @admin
  end

  test 'reset generates a unique temporary password, shown once, and the old one stops working' do
    target = build_user(name: 'Maria Souza')

    patch reset_password_user_path(target)

    assert_response :success
    assert_equal 'no-store', response.headers['Cache-Control']
    password = css_select('.users-reset__code code').first.text
    assert_equal UsersController::TEMPORARY_PASSWORD_LENGTH, password.length
    assert target.reload.valid_password?(password)
    assert_not target.valid_password?('password123')
    assert_not_includes response.body, 'mudar@123'
  end

  test 'each reset produces a different password' do
    target = build_user

    patch reset_password_user_path(target)
    first = css_select('.users-reset__code code').first.text
    patch reset_password_user_path(target)

    assert_not_equal first, css_select('.users-reset__code code').first.text
  end

  test 'an admin cannot reset their own password here' do
    patch reset_password_user_path(@admin)

    assert_redirected_to edit_user_path(@admin)
    assert @admin.reload.valid_password?('password123')
  end

  test 'the edit page shows the avatar and the reset card, but not for yourself' do
    target = build_user(name: 'Maria Souza')

    get edit_user_path(target)
    assert_select '.users-form-page__avatar', text: 'MS'
    assert_select 'form[action=?]', reset_password_user_path(target)

    get edit_user_path(@admin)
    assert_select 'form[action=?]', reset_password_user_path(@admin), count: 0
  end

  test 'the profile and client selects use the styled select' do
    get new_user_path

    assert_select 'select#user_profile_id[data-custom-select]'
    assert_select 'select#user_client_id[data-custom-select]'
  end

  test 'non admins cannot reset passwords' do
    sign_out @admin
    sign_in build_user(name: 'Comum')
    target = build_user

    patch reset_password_user_path(target)

    assert_redirected_to crm_path
    assert target.reload.valid_password?('password123')
  end

  test 'the list uses the avatar with the tone of each name' do
    build_user(name: 'Maria Souza')

    get users_path

    assert_select '.users-page__avatar.avatar', text: 'MS'
  end
end
