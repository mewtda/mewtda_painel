require 'test_helper'

class EmailSuppressionsControllerTest < ActionDispatch::IntegrationTest
  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com", password: 'password123',
                 password_confirmation: 'password123', profile_id: Profile::USER, client:)
  end

  test 'index lists only the current client refusal list' do
    client = build_client
    EmailSuppression.unsubscribe!(client, 'ana@example.com')
    EmailSuppression.unsubscribe!(build_client, 'outro@example.com')
    sign_in build_user(client:)

    get email_suppressions_path

    assert_response :success
    assert_match 'ana@example.com', response.body
    assert_no_match 'outro@example.com', response.body
  end

  test 'create adds an email manually' do
    client = build_client
    sign_in build_user(client:)

    post email_suppressions_path, params: { email_suppression: { email: 'Bia@Example.com' } }

    assert_redirected_to email_suppressions_path
    assert_equal 'manual', client.email_suppressions.find_by(email: 'bia@example.com').source
  end

  test 'create rejects an invalid email' do
    client = build_client
    sign_in build_user(client:)

    assert_no_difference 'EmailSuppression.count' do
      post email_suppressions_path, params: { email_suppression: { email: 'nao-e-email' } }
    end
  end

  test 'destroy removes an email from the list, scoped to the client' do
    client = build_client
    mine = EmailSuppression.unsubscribe!(client, 'ana@example.com')
    theirs = EmailSuppression.unsubscribe!(build_client, 'ana@example.com')
    sign_in build_user(client:)

    delete email_suppression_path(theirs)
    delete email_suppression_path(mine)

    assert_not EmailSuppression.exists?(mine.id)
    assert EmailSuppression.exists?(theirs.id)
  end
end
