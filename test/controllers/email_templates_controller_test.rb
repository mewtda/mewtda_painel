require 'test_helper'

class EmailTemplatesControllerTest < ActionDispatch::IntegrationTest
  def build_user(client:)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }

    User.create!(
      name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
      password: 'password123', password_confirmation: 'password123',
      profile_id: Profile::USER, client: client
    )
  end

  def build_client
    Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
  end

  def valid_blocks
    [{ type: 'heading', text: 'Bem-vindo(a)!' }, { type: 'text', text: 'Texto' }, { type: 'button', text: 'Ver produtos' }]
  end

  def valid_params
    { name: 'Boas-vindas', subject: 'Oi!', blocks_json: valid_blocks.to_json }
  end

  def png_upload
    Rack::Test::UploadedFile.new(StringIO.new("\x89PNG\r\n\x1a\nfake"), 'image/png', true, original_filename: 'foto.png')
  end

  test 'index lists only the current client templates' do
    client = build_client
    other_client = build_client
    EmailTemplate.create!(valid_params.merge(client: client))
    EmailTemplate.create!(valid_params.merge(client: other_client, name: 'De outro cliente'))
    sign_in build_user(client: client)

    get email_templates_path

    assert_response :success
    assert_match 'Boas-vindas', response.body
    assert_no_match 'De outro cliente', response.body
  end

  test 'new without a preset renders a blank form' do
    sign_in build_user(client: build_client)

    get new_email_template_path

    assert_response :success
  end

  test 'new prefills attributes from a preset' do
    sign_in build_user(client: build_client)

    get new_email_template_path(preset: 'cart_recovery')

    assert_response :success
    assert_match 'Carrinho abandonado', response.body
  end

  test 'create saves a template scoped to the current client' do
    client = build_client
    sign_in build_user(client: client)

    assert_difference 'EmailTemplate.count', 1 do
      post email_templates_path, params: { email_template: valid_params }
    end

    assert_equal client, EmailTemplate.last.client
    assert_redirected_to email_templates_path
  end

  test 'create re-renders the form with errors when invalid' do
    sign_in build_user(client: build_client)

    assert_no_difference 'EmailTemplate.count' do
      post email_templates_path, params: { email_template: valid_params.merge(name: '') }
    end

    assert_response :unprocessable_entity
  end

  test 'update changes an existing template' do
    client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: client))
    sign_in build_user(client: client)

    patch email_template_path(template), params: { email_template: { name: 'Novo nome' } }

    assert_redirected_to email_templates_path
    assert_equal 'Novo nome', template.reload.name
  end

  test 'create stores blocks in the submitted order' do
    sign_in build_user(client: build_client)

    post email_templates_path, params: { email_template: valid_params }

    assert_equal %w[heading text button], EmailTemplate.last.blocks.map { |b| b['type'] }
  end

  test 'create without blocks re-renders the form' do
    sign_in build_user(client: build_client)

    assert_no_difference 'EmailTemplate.count' do
      post email_templates_path, params: { email_template: valid_params.merge(blocks_json: '[]') }
    end

    assert_response :unprocessable_entity
    assert_match 'Adicione pelo menos um bloco', response.body
  end

  test 'preview renders the blocks with variables and selectable block ids' do
    sign_in build_user(client: build_client)
    blocks = [{ id: 'abc', type: 'heading', text: 'Oi {nome}' }, { type: 'text', text: '**forte** <script>x</script>' }]

    post preview_email_templates_path, params: { email_template: valid_params.merge(blocks_json: blocks.to_json) }

    html = response.parsed_body['html']
    assert_match 'Oi Maria', html
    assert_match 'data-block-id="abc"', html
    assert_match '<strong>forte</strong>', html
    assert_no_match '<script>x', html
    assert_match 'Não quero mais receber estes e-mails', html
  end

  test 'upload_image stores an image and returns its signed id' do
    sign_in build_user(client: build_client)

    assert_difference 'ActiveStorage::Blob.count', 1 do
      post upload_image_email_templates_path, params: { file: png_upload }
    end

    assert_response :success
    assert ActiveStorage::Blob.find_signed(response.parsed_body['signed_id'])
  end

  test 'upload_image rejects files that are not images' do
    sign_in build_user(client: build_client)
    file = Rack::Test::UploadedFile.new(StringIO.new('<svg/>'), 'image/svg+xml', original_filename: 'x.svg')

    assert_no_difference 'ActiveStorage::Blob.count' do
      post upload_image_email_templates_path, params: { file: file }
    end

    assert_response :unprocessable_entity
  end

  test 'saving a template attaches the uploaded block images to it' do
    client = build_client
    sign_in build_user(client: client)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('img'), filename: 'a.png', content_type: 'image/png')
    blocks = [{ type: 'image', image_id: blob.signed_id }]

    post email_templates_path, params: { email_template: valid_params.merge(blocks_json: blocks.to_json) }

    assert_includes EmailTemplate.last.block_images.blobs, blob
  end

  test 'destroy removes the template' do
    client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: client))
    sign_in build_user(client: client)

    assert_difference 'EmailTemplate.count', -1 do
      delete email_template_path(template)
    end
  end

  test 'cannot edit a template belonging to another client' do
    other_client = build_client
    template = EmailTemplate.create!(valid_params.merge(client: other_client))
    sign_in build_user(client: build_client)

    get edit_email_template_path(template)

    assert_redirected_to email_templates_path
  end
end
