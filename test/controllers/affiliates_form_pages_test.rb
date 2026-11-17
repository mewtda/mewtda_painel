require 'test_helper'

class AffiliatesFormPagesTest < ActionDispatch::IntegrationTest
  setup do
    Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }
    Profile.find_or_create_by!(id: Profile::AFFILIATE) { |p| p.name = 'Afiliado' }
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com", site_url: 'https://loja.com.br')
    @admin = User.create!(name: 'Chefe', email: "a-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                          password_confirmation: 'password123', profile_id: Profile::ADMIN, client: @client)
    sign_in @admin
  end

  test 'new, edit and settings follow the shared form page pattern' do
    affiliate = User.create!(name: 'Maria Souza', email: "m-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                             password_confirmation: 'password123', profile_id: Profile::AFFILIATE, client: @client,
                             utm_code: "maria-#{SecureRandom.hex(2)}")

    [new_affiliate_path, edit_affiliate_path(affiliate), settings_affiliates_path].each do |path|
      get path

      assert_response :success, path
      assert_select '.users-form-page .users-form-page__header', 1, path
      assert_select '.users-form-page__footer', 1, path
      assert_select '.affiliates-form__card-header, .cpform-card', 0, path
    end
  end

  test 'the edit page shows the avatar and the id of the affiliate' do
    affiliate = User.create!(name: 'Maria Souza', email: "m-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                             password_confirmation: 'password123', profile_id: Profile::AFFILIATE, client: @client,
                             utm_code: "maria-#{SecureRandom.hex(2)}")

    get edit_affiliate_path(affiliate)

    assert_select '.users-form-page__avatar', text: 'MS'
    assert_select '.users-form-page__subtitle', text: /ID ##{affiliate.id}/
  end
end
