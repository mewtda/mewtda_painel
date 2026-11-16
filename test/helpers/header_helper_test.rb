require 'test_helper'

class HeaderHelperTest < ActionView::TestCase
  def build_user(admin: false, affiliate: false, client: nil)
    profile_id =
      if admin then Profile::ADMIN
      elsif affiliate then Profile::AFFILIATE
      else Profile::USER
      end
    Profile.find_or_create_by!(id: profile_id) { |p| p.name = profile_id.to_s }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: profile_id, client: client, utm_code: affiliate ? SecureRandom.hex(4) : nil
    )
  end

  test 'affiliate only sees Meus Eventos' do
    user = build_user(affiliate: true)

    items = searchable_nav_items(user)

    assert_equal ['Meus Eventos'], items.map { |i| i[:label] }
  end

  test 'common user without a client does not see Dashboard metas' do
    user = build_user

    labels = searchable_nav_items(user).map { |i| i[:label] }

    refute_includes labels, 'Dashboard metas'
    assert_includes labels, 'Trackeamento site'
    assert_includes labels, 'Pedidos'
    assert_includes labels, 'Configurações'
  end

  test 'common user with a client sees Dashboard metas' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    user = build_user(client: client)

    assert_includes searchable_nav_items(user).map { |i| i[:label] }, 'Dashboard metas'
  end

  test 'admin sees admin-only items and Dashboard metas even without a client' do
    admin = build_user(admin: true)

    labels = searchable_nav_items(admin).map { |i| i[:label] }

    assert_includes labels, 'Dashboard metas'
    assert_includes labels, 'Usuários'
    assert_includes labels, 'Perfis'
    assert_includes labels, 'Sidekiq'
    assert_includes labels, 'Try-On Virtual'
    refute_includes labels, 'Configurações'
  end

  test 'every item has a label, url and icon' do
    admin = build_user(admin: true)

    searchable_nav_items(admin).each do |item|
      assert item[:label].present?
      assert item[:url].present?
      assert item[:icon].present?
    end
  end
end
