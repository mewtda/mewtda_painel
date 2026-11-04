require 'test_helper'

class Whatsapp::ConnectionTest < ActiveSupport::TestCase
  def setup
    @a = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    @b = Client.create!(name: 'Loja B', email: "b-#{SecureRandom.hex(4)}@example.com")
    @a1 = @a.whatsapp_connections.create!(name: 'A1')
    @a2 = @a.whatsapp_connections.create!(name: 'A2')
    @b1 = @b.whatsapp_connections.create!(name: 'B1')
  end

  def create_user(client, profile_id: nil)
    Profile.find_or_create_by!(id: 1) { |p| p.name = 'Admin' } if profile_id
    User.create!(name: 'Fulano', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'senha123456',
                 client: client, profile_id: profile_id)
  end

  test 'client_id não muda depois de criado' do
    @a1.update(client_id: @b.id)
    assert_equal @a.id, @a1.reload.client_id
  end

  test 'gera instance_key e webhook_token' do
    assert_match(/\Amewtda-\h{32}\z/, @a1.instance_key)
    assert @a1.webhook_token.present?
  end

  test 'visible_to: usuário só vê números do próprio cliente com permissão' do
    user = create_user(@a)
    Whatsapp::Membership.create!(connection: @a1, user: user)

    assert_equal [@a1], Whatsapp::Connection.visible_to(user, client: @a).to_a
    assert_empty Whatsapp::Connection.visible_to(user, client: @b)
    assert_empty Whatsapp::Connection.visible_to(nil, client: @a)
  end

  test 'visible_to: admin vê só os números do cliente em contexto' do
    admin = create_user(nil, profile_id: 1)

    assert_equal [@a1, @a2].sort_by(&:id), Whatsapp::Connection.visible_to(admin, client: @a).sort_by(&:id)
    assert_equal [@b1], Whatsapp::Connection.visible_to(admin, client: @b).to_a
  end

  test 'administrable_by? só para admin' do
    assert Whatsapp::Connection.administrable_by?(create_user(nil, profile_id: 1))
    refute Whatsapp::Connection.administrable_by?(create_user(@a))
    refute Whatsapp::Connection.administrable_by?(nil)
  end
end
