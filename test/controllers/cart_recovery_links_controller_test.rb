require 'test_helper'

class CartRecoveryLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             site_url: 'https://loja.com.br')
    @checkout = @client.abandoned_checkouts.create!(
      shopify_checkout_id: SecureRandom.hex(6), checkout_created_at: Time.current,
      recovery_url: 'https://loja.com.br/123/checkouts/abc/recover?key=k'
    )
  end

  test 'com cupom passa pelo /discount da loja e segue para o checkout' do
    @checkout.update!(first_coupon_code: 'FARAH')

    get cart_recovery_link_path(slug: @checkout.slug)

    assert_redirected_to 'https://loja.com.br/discount/FARAH?redirect=%2F123%2Fcheckouts%2Fabc%2Frecover%3Fkey%3Dk'
  end

  test 'sem cupom vai direto para o checkout' do
    get cart_recovery_link_path(slug: @checkout.slug)

    assert_redirected_to 'https://loja.com.br/123/checkouts/abc/recover?key=k'
  end

  test 'checkout sem link vai para o site da loja' do
    @checkout.update!(recovery_url: nil)

    get cart_recovery_link_path(slug: @checkout.slug)

    assert_redirected_to 'https://loja.com.br'
  end

  test 'slug desconhecido vai para a página inicial' do
    get cart_recovery_link_path(slug: 'naoexiste')

    assert_redirected_to root_url
  end
end
