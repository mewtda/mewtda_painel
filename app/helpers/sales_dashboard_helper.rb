module SalesDashboardHelper
  # Botão que copia a consulta ShopifyQL usada na métrica, para colar no
  # relatório da Shopify e conferir o número.
  def shopify_query_button(query, note: nil)
    return if query.blank?

    title = ['Copiar consulta da Shopify', note].compact.join(' — ')
    tag.button(type: 'button', class: 'sd-copy-query', title: title, 'aria-label': title,
               data: { query: query }) { tag.i(class: 'fa-regular fa-copy') }
  end
  def currency(value)
    number_to_currency(value, unit: 'R$', separator: ',', delimiter: '.')
  end

  def month_label(date)
    names = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro]
    "#{names[date.month - 1]}/#{date.year}"
  end

  SESSIONS_DISCLAIMER = 'A Shopify não disponibiliza sessões/conversão via API — este número vem do nosso ' \
                        'pixel de rastreamento próprio e pode não bater exatamente com o relatório nativo ' \
                        'da Shopify.'.freeze

  # Ícone de alerta com tooltip explicando que Acessos/Taxa de Conversão vêm
  # do pixel próprio (a Shopify não expõe sessões/conversão via API).
  def sessions_disclaimer_icon
    content_tag(:i, '', class: 'fa-solid fa-triangle-exclamation sd-disclaimer-icon', title: SESSIONS_DISCLAIMER)
  end
end
