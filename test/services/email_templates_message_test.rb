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
end
