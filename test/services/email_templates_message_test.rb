require 'test_helper'

class EmailTemplatesMessageTest < ActiveSupport::TestCase
  def template(blocks, **attrs)
    client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com")
    EmailTemplate.new(client:, name: 'T', subject: 'Oi {nome}', blocks:, **attrs)
  end

  test 'renders blocks in order, with variables, formatting and the unsubscribe footer' do
    message = EmailTemplates::Message.new(
      template([
        { 'type' => 'text', 'text' => 'Primeiro **forte** e [link](https://loja.com) <b>cru</b>' },
        { 'type' => 'heading', 'text' => 'Segundo {nome}' },
        { 'type' => 'button', 'text' => 'Comprar', 'link' => '' }
      ]),
      variables: { nome: 'Ana', loja: 'Loja Teste' }, default_url: 'https://loja.com',
      unsubscribe_url: 'https://www.mewtda.com.br/widget/descadastrar/t'
    )
    html = message.html

    assert_equal 'Oi Ana', message.subject
    assert html.index('Primeiro') < html.index('Segundo Ana')
    assert_match '<strong>forte</strong>', html
    assert_match '<a href="https://loja.com"', html
    assert_match '&lt;b&gt;cru&lt;/b&gt;', html
    assert_match 'href="https://loja.com" target="_blank"', html
    assert_match 'https://www.mewtda.com.br/widget/descadastrar/t', html
    assert_no_match 'data-block-id', html
  end

  test 'text version lists content and the unsubscribe link' do
    message = EmailTemplates::Message.new(
      template([{ 'type' => 'heading', 'text' => 'Olá' }, { 'type' => 'coupon', 'code' => 'X10', 'label' => 'Cupom' }]),
      variables: { loja: 'Loja Teste' }, unsubscribe_url: 'https://x.test/u'
    )

    assert_equal "Loja Teste\n\nOlá\n\nCupom: X10\n\nNão quero mais receber estes e-mails: https://x.test/u", message.text
  end

  test 'product block uses the product data and is skipped without a product' do
    tpl = template([{ 'type' => 'product', 'button_text' => 'Comprar agora' }], trigger_kind: :back_in_stock)
    with_product = EmailTemplates::Message.new(tpl, product: { title: 'Vestido', variant: 'M', image: 'https://cdn/x.jpg', url: 'https://loja.com/p' })
    without = EmailTemplates::Message.new(tpl)

    assert_match 'Vestido', with_product.html
    assert_match 'https://loja.com/p', with_product.html
    assert_no_match 'Comprar agora', without.html
  end

  test 'menu block renders the links, falls back to the store url and lists them in the text version' do
    blocks = [{ 'type' => 'menu', 'uppercase' => true,
                'items' => [{ 'label' => 'Mulher', 'link' => 'https://loja.com/mulher' }, { 'label' => 'Sale', 'link' => '' }] }]
    message = EmailTemplates::Message.new(template(blocks), default_url: 'https://loja.com')

    assert_match 'href="https://loja.com/mulher"', message.html
    assert_match 'href="https://loja.com"', message.html
    assert_match 'text-transform: uppercase', message.html
    assert_match 'Mulher: https://loja.com/mulher', message.text
  end

  test 'social block paints the background with the chosen color and picks a glyph that contrasts' do
    dark = [{ 'type' => 'social', 'instagram' => 'https://instagram.com/loja', 'color' => '#111111', 'shape' => 'square' }]
    light = [{ 'type' => 'social', 'instagram' => 'https://instagram.com/loja', 'color' => '#f1f1f4' }]
    dark_html = EmailTemplates::Message.new(template(dark)).html
    light_html = EmailTemplates::Message.new(template(light)).html

    assert_match 'https://www.mewtda.com.br/email/icons/instagram-white.png', dark_html
    assert_match 'border-radius: 0', dark_html
    assert_match 'https://www.mewtda.com.br/email/icons/instagram-black.png', light_html
    assert_match 'border-radius: 50%', light_html
  end

  test 'social block with network colors uses the brand color and ignores networks without link' do
    blocks = [{ 'type' => 'social', 'tone' => 'brand', 'instagram' => 'https://instagram.com/loja' }]
    html = EmailTemplates::Message.new(template(blocks)).html

    assert_match '#E4405F', html
    assert_no_match 'facebook', html
  end

  test 'social block saved before the colors falls back to dark icons' do
    blocks = [{ 'type' => 'social', 'instagram' => 'https://instagram.com/loja' }]
    html = EmailTemplates::Message.new(template(blocks)).html

    assert_match '#111111', html
    assert_match '/email/icons/instagram-white.png', html
  end

  test 'products block renders the chosen products in a grid and only keeps safe fields' do
    blocks = EmailTemplates::Blocks.sanitize([
      { 'type' => 'products', 'collection' => 'novidades', 'button_text' => 'Ver', 'show_price' => true,
        'items' => [
          { 'title' => 'Vestido Longo', 'price' => 'R$ 599,00', 'photo' => 'https://cdn.shopify.com/v.jpg',
            'link' => 'https://lojaoneway.com/products/vestido', 'extra' => 'x' },
          { 'title' => 'Calça', 'price' => 'R$ 209,93', 'photo' => 'http://inseguro.com/c.jpg',
            'link' => 'javascript:alert(1)' },
          { 'title' => '' }
        ] }
    ])
    items = blocks.first['items']
    assert_equal 2, items.size
    assert_equal %w[link photo price title], items.first.keys.sort
    assert_equal '', items.last['photo'], 'só aceita foto https'
    assert_equal '', items.last['link']

    message = EmailTemplates::Message.new(template(blocks), variables: { loja: 'Loja' }, default_url: 'https://lojaoneway.com')
    html = message.html
    assert_match 'Vestido Longo', html
    assert_match 'R$ 599,00', html
    assert_match 'src="https://cdn.shopify.com/v.jpg"', html
    assert_match 'href="https://lojaoneway.com/products/vestido"', html
    assert_no_match 'inseguro.com', html
    assert_no_match 'javascript:', html
    assert_match 'email-product', html
    assert_match "Vestido Longo: https://lojaoneway.com/products/vestido", message.text
  end
end
