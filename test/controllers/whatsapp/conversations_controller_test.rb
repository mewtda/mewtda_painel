require 'test_helper'

class Whatsapp::ConversationsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @a = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    @b = Client.create!(name: 'Loja B', email: "b-#{SecureRandom.hex(4)}@example.com", whatsapp_provider: 'evolution')
    Profile.find_or_create_by!(id: Profile::ADMIN) { |p| p.name = 'Admin' }
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'Usuário' }
    @admin = make_user(Profile::ADMIN, @a)
    @user_a = make_user(Profile::USER, @a)
    @a1 = @a.whatsapp_connections.create!(name: 'A1', state: 'connected')
    @a2 = @a.whatsapp_connections.create!(name: 'A2', state: 'connected')
    @b1 = @b.whatsapp_connections.create!(name: 'B1', state: 'connected')
    @conv_a1 = conversation(@a1, '5511911110001')
    @conv_a2 = conversation(@a2, '5511911110002')
    @conv_b1 = conversation(@b1, '5511911110003')
  end

  def make_user(profile, client)
    User.create!(name: 'Fulano', email: "u-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                 password_confirmation: 'password123', profile_id: profile, client: client)
  end

  def conversation(connection, digits)
    contact = connection.contacts.create!(provider_jid: "#{digits}@s.whatsapp.net", phone: "+#{digits}")
    connection.conversations.create!(contact: contact, last_message_at: Time.current)
  end

  def select_client(client)
    post '/crm/update_selected_client', params: { client_id: client.id }, as: :json
    assert_response :success
  end

  test 'usuário sem acesso ao número não abre a conversa; com acesso abre' do
    sign_in @user_a
    get "/crm/whatsapp/conversations/#{@conv_a1.id}.json"
    assert_response :not_found

    @a1.memberships.create!(user: @user_a)
    get "/crm/whatsapp/conversations/#{@conv_a1.id}.json"
    assert_response :success
    assert_equal @conv_a1.id, response.parsed_body['id']
  end

  test 'conversa de número de outro cliente é 404 mesmo para admin com o cliente A selecionado' do
    sign_in @admin
    select_client(@a)

    get "/crm/whatsapp/conversations/#{@conv_b1.id}.json"
    assert_response :not_found
    get "/crm/whatsapp/conversations/#{@conv_b1.id}/messages.json"
    assert_response :not_found
    patch "/crm/whatsapp/conversations/#{@conv_b1.id}/auto_reply", params: { paused: true }, as: :json
    assert_response :not_found
    # client_id na URL não troca o cliente do atendimento.
    get "/crm/whatsapp/conversations/#{@conv_b1.id}.json", params: { client_id: @b.id }
    assert_response :not_found
  end

  test 'index lista só conversas e números visíveis ao usuário' do
    @a1.memberships.create!(user: @user_a)
    sign_in @user_a

    get '/crm/whatsapp/conversations.json'

    assert_response :success
    assert_equal [@conv_a1.id], response.parsed_body['conversations'].map { |c| c['id'] }
    assert_equal [@a1.id], response.parsed_body['connections'].map { |c| c['id'] }

    get '/crm/whatsapp/conversations.json', params: { q: '10001' }
    assert_equal [@conv_a1.id], response.parsed_body['conversations'].map { |c| c['id'] }
    get '/crm/whatsapp/conversations.json', params: { q: 'ninguém' }
    assert_empty response.parsed_body['conversations']
  end

  test 'index com campaign_id traz só conversas dos números da automação' do
    campaign = @a.campaigns.create!(name: 'Recuperação', kind: 'cart_recovery', message: 'Oi', resend_message: 'Volta',
                                    start_date: Date.current - 1.day, end_date: Date.current + 1.year,
                                    send_delay_minutes: 60)
    Whatsapp::CampaignConnection.create!(campaign: campaign, connection: @a2)
    sign_in @admin
    select_client(@a)

    get '/crm/whatsapp/conversations.json', params: { campaign_id: campaign.id }

    assert_response :success
    assert_equal [@conv_a2.id], response.parsed_body['conversations'].map { |c| c['id'] }
    assert_equal [@a2.id], response.parsed_body['connections'].map { |c| c['id'] }
  end

  test 'campaign_id de outro cliente é 404' do
    campaign = @b.campaigns.create!(name: 'Recuperação', kind: 'cart_recovery', message: 'Oi', resend_message: 'Volta',
                                    start_date: Date.current - 1.day, end_date: Date.current + 1.year,
                                    send_delay_minutes: 60)
    sign_in @admin
    select_client(@a)

    get '/crm/whatsapp/conversations.json', params: { campaign_id: campaign.id }
    assert_response :not_found
  end

  test 'show traz o checkout mais recente da conversa e a pausa da resposta automática' do
    @a.abandoned_checkouts.create!(shopify_checkout_id: SecureRandom.hex(6), total_price: 10, recovery_url: 'http://old',
                                   whatsapp_conversation_id: @conv_a1.id, first_notified_at: 2.days.ago,
                                   created_at: 2.days.ago)
    @a.abandoned_checkouts.create!(shopify_checkout_id: SecureRandom.hex(6), total_price: 99.9, recovery_url: 'http://new',
                                   whatsapp_conversation_id: @conv_a1.id, first_notified_at: 1.hour.ago,
                                   second_notified_at: 5.minutes.ago)
    sign_in @admin
    select_client(@a)

    get "/crm/whatsapp/conversations/#{@conv_a1.id}.json"

    assert_response :success
    body = response.parsed_body
    assert_equal({ 'status' => 'second_sent', 'total_price' => '99.9', 'recovery_url' => 'http://new' }, body['checkout'])
    assert_equal false, body['auto_reply_paused']
  end

  test 'PATCH auto_reply pausa e retoma a resposta automática' do
    @a1.memberships.create!(user: @user_a)
    sign_in @user_a

    patch "/crm/whatsapp/conversations/#{@conv_a1.id}/auto_reply", params: { paused: true }, as: :json
    assert_response :success
    assert @conv_a1.reload.auto_reply_paused

    patch "/crm/whatsapp/conversations/#{@conv_a1.id}/auto_reply", params: { paused: false }, as: :json
    assert_response :success
    assert_not @conv_a1.reload.auto_reply_paused
  end

  test 'update finaliza e reabre a conversa' do
    sign_in @admin
    select_client(@a)

    patch "/crm/whatsapp/conversations/#{@conv_a1.id}", params: { operation: 'close' }, as: :json
    assert_response :success
    assert_equal 'closed', @conv_a1.reload.state

    patch "/crm/whatsapp/conversations/#{@conv_a1.id}", params: { operation: 'take' }, as: :json
    assert_response :unprocessable_entity
  end

  test 'create abre conversa só em número visível' do
    sign_in @user_a
    post '/crm/whatsapp/conversations', params: { connection_id: @a1.id, phone: '+55 11 98888-7777' }, as: :json
    assert_response :not_found

    @a1.memberships.create!(user: @user_a)
    assert_difference 'Whatsapp::Conversation.count', 1 do
      post '/crm/whatsapp/conversations', params: { connection_id: @a1.id, phone: '+55 11 98888-7777' }, as: :json
    end
    assert_response :created
    assert_equal @a1.id, Whatsapp::Conversation.find(response.parsed_body['id']).connection_id
  end

  test 'read marca a conversa como lida' do
    sign_in @admin
    select_client(@a)
    message = @conv_a1.messages.create!(connection: @a1, direction: 'incoming', state: 'received',
                                        body: 'Oi', sent_at: Time.current)
    assert_equal 1, @conv_a1.unread_count(@admin)

    post "/crm/whatsapp/conversations/#{@conv_a1.id}/read", params: { last_message_id: message.id }, as: :json

    assert_response :no_content
    assert_equal 0, @conv_a1.unread_count(@admin)
  end

  test 'tela de conversas renderiza o inbox com a base da API' do
    @a1.memberships.create!(user: @user_a)
    sign_in @user_a

    get '/crm/whatsapp/conversations'

    assert_response :success
    assert_select '#wa-inbox[data-api-base="/crm/whatsapp"]'
    assert_select '.wa-number-tab[data-id=?]', @a1.id.to_s
    assert_select '.wa-number-tab[data-id=?]', @a2.id.to_s, count: 0
    assert_select '#wa-auto-reply', count: 0 # resposta automática ainda não está pronta para o cliente
    assert_select 'a.crm-sidebar__link[href="/crm/whatsapp/conversations"]', text: /Conversas/
  end

  test 'botão de pausar a resposta automática só aparece quando o cliente tem a resposta pronta' do
    sign_in @admin
    select_client(@a)

    @a.stub(:auto_reply_ready?, true) do
      Client.stub(:find_by, @a) do
        get '/crm/whatsapp/conversations'
        assert_select '#wa-auto-reply', text: /Pausar resposta automática/
        get "/crm/whatsapp/conversations/#{@conv_a1.id}.json"
        assert_equal true, response.parsed_body['auto_reply_available']
      end
    end
  end

  test 'tela com campaign_id mostra só as abas dos números da automação' do
    campaign = @a.campaigns.create!(name: 'Recuperação', kind: 'cart_recovery', message: 'Oi', resend_message: 'Volta',
                                    start_date: Date.current - 1.day, end_date: Date.current + 1.year,
                                    send_delay_minutes: 60)
    Whatsapp::CampaignConnection.create!(campaign: campaign, connection: @a2)
    sign_in @admin
    select_client(@a)

    get '/crm/whatsapp/conversations', params: { campaign_id: campaign.id }

    assert_response :success
    assert_select '#wa-inbox[data-campaign-id=?]', campaign.id.to_s
    assert_select '.wa-number-tab', count: 1
    assert_select '.wa-number-tab[data-id=?]', @a2.id.to_s
  end

  test 'admin sem cliente selecionado vê aviso e nenhuma conversa' do
    admin = make_user(Profile::ADMIN, nil)
    sign_in admin

    get '/crm/whatsapp/conversations'
    assert_response :success
    assert_includes response.body, 'Nenhum cliente selecionado'
    assert_select '.wa-workspace', count: 0

    get "/crm/whatsapp/conversations/#{@conv_a1.id}.json"
    assert_response :not_found
  end
end
