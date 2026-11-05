require 'test_helper'

class Whatsapp::ConnectionsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @a = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    @b = Client.create!(name: 'Loja B', email: "b-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'Usuário' }
    @admin = make_user(Profile::ADMIN, nil)
    @user_a = make_user(Profile::USER, @a)
    @user_b = make_user(Profile::USER, @b)
  end

  def make_user(profile, client)
    User.create!(name: 'Fulano', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                 password_confirmation: 'password123', profile_id: profile, client: client)
  end

  def path(client = @a, suffix = '') = "/crm/clients/#{client.id}/whatsapp/connections#{suffix}"

  test 'admin cria número para o cliente A com usuários do cliente' do
    sign_in @admin
    Whatsapp::Providers::Evolution.stub :configured?, true do
      assert_enqueued_with(job: Whatsapp::ControlJob) do
        post path, params: { name: 'Vendas', user_ids: [@user_a.id] }, as: :json
      end
    end

    assert_response :created
    connection = Whatsapp::Connection.last
    assert_equal @a.id, connection.client_id
    assert_equal [@user_a.id], connection.users.ids
  end

  test 'user_ids de outro cliente retornam 422 e nada é criado' do
    sign_in @admin
    Whatsapp::Providers::Evolution.stub :configured?, true do
      assert_no_difference 'Whatsapp::Connection.count' do
        post path, params: { name: 'Vendas', user_ids: [@user_b.id] }, as: :json
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.parsed_body['error'], 'Selecione somente usuários deste cliente.'
  end

  test 'não-admin não gerencia números' do
    sign_in @user_a
    get path
    assert_response :forbidden
    assert_no_difference 'Whatsapp::Connection.count' do
      post path, params: { name: 'X' }, as: :json
    end
    assert_response :forbidden
  end

  test 'index do cliente A não lista números do cliente B' do
    mine = @a.whatsapp_connections.create!(name: 'A1')
    @b.whatsapp_connections.create!(name: 'B1')
    sign_in @admin

    get path(@a, '.json')

    assert_response :success
    assert_equal [mine.id], response.parsed_body['connections'].map { |c| c['id'] }
    assert_equal [@user_a.id], response.parsed_body['users'].map { |u| u['id'] }
  end

  test 'não atualiza nem conecta número de outro cliente' do
    other = @b.whatsapp_connections.create!(name: 'B1')
    sign_in @admin

    patch path(@a, "/#{other.id}"), params: { name: 'Hack' }, as: :json
    assert_response :not_found
    post path(@a, "/#{other.id}/connect"), as: :json
    assert_response :not_found
    assert_equal 'B1', other.reload.name
  end

  test 'update troca nome e acesso' do
    connection = @a.whatsapp_connections.create!(name: 'A1')
    sign_in @admin

    patch path(@a, "/#{connection.id}"), params: { name: 'Novo', user_ids: [@user_a.id] }, as: :json

    assert_response :success
    assert_equal 'Novo', connection.reload.name
    assert_equal [@user_a.id], connection.users.ids
  end

  test 'destroy exclui número sem mensagens' do
    connection = @a.whatsapp_connections.create!(name: 'A1')
    sign_in @admin

    assert_difference 'Whatsapp::Connection.count', -1 do
      delete path(@a, "/#{connection.id}"), as: :json
    end
    assert_response :no_content
  end

  test 'destroy recusa número com mensagens' do
    connection = @a.whatsapp_connections.create!(name: 'A1')
    sign_in @admin
    contact = connection.contacts.create!(provider_jid: '5511988887777@s.whatsapp.net')
    conversation = connection.conversations.create!(contact: contact)
    connection.messages.create!(conversation: conversation, direction: 'incoming', state: 'received', body: 'Oi',
                                sent_at: Time.current)

    assert_no_difference 'Whatsapp::Connection.count' do
      delete path(@a, "/#{connection.id}"), as: :json
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body['error'], 'Desconecte em vez de excluir'
  end

  test 'connect e disconnect pedem controle' do
    connection = @a.whatsapp_connections.create!(name: 'A1')
    sign_in @admin

    assert_enqueued_with(job: Whatsapp::ControlJob) do
      post path(@a, "/#{connection.id}/disconnect"), as: :json
    end
    assert_response :accepted
    assert_equal 'disconnecting', connection.reload.state
  end

  test 'edição do cliente mostra os números e não tem mais Z-API' do
    sign_in @admin
    get edit_client_path(@a)

    assert_response :success
    assert_select '#wan-section[data-base=?]', "/crm/clients/#{@a.id}/whatsapp/connections"
    assert_select 'select#client_whatsapp_provider', count: 0
    assert_select 'input#client_zapi_instance_id', count: 0
  end
end
