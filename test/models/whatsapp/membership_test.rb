require 'test_helper'

class Whatsapp::MembershipTest < ActiveSupport::TestCase
  def setup
    @a = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    @b = Client.create!(name: 'Loja B', email: "b-#{SecureRandom.hex(4)}@example.com")
    @connection = @a.whatsapp_connections.create!(name: 'A1')
  end

  def create_user(client)
    User.create!(name: 'Fulano', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'senha123456', client: client)
  end

  test 'não permite usuário de outro cliente' do
    membership = Whatsapp::Membership.new(connection: @connection, user: create_user(@b))

    refute membership.valid?
    assert membership.errors[:user].any?
  end

  test 'permite usuário do mesmo cliente' do
    assert Whatsapp::Membership.new(connection: @connection, user: create_user(@a)).valid?
  end
end
