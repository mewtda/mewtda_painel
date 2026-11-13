module BackInStockHelper
  STATUS_LABELS = { 'pending' => 'Aguardando', 'notified' => 'Avisados', 'cancelled' => 'Cancelados' }.freeze
  SORT_LABELS = { 'demand' => 'Mais pedidos', 'value' => 'Maior valor', 'trending' => 'Em alta' }.freeze

  def back_in_stock_snippet(setting)
    %(<script src="#{setting.script_url}" data-token="#{setting.public_token}" data-avise-me="{{ product.metafields.mewtda.avise_me.value | default: false }}" defer></script>)
  end

  def site_url_settings_path(client)
    current_user.admin? ? edit_client_path(client) : settings_affiliates_path
  end

  def back_in_stock_status_label(status)
    STATUS_LABELS.fetch(status)
  end

  def back_in_stock_sort_options(selected)
    options_for_select(SORT_LABELS.invert, selected)
  end

  def back_in_stock_waiting(group)
    days = (Date.current - group.first_requested_at.in_time_zone.to_date).to_i
    days.zero? ? 'Esperando desde hoje' : "Esperando há #{days} #{'dia'.pluralize(days)}"
  end

  def back_in_stock_requested_range(group)
    first, last = [group.first_requested_at, group.last_requested_at].map { |time| time.in_time_zone.to_date }
    "Primeiro pedido em #{first.strftime('%d/%m/%Y')} · último em #{last.strftime('%d/%m/%Y')}"
  end

  def back_in_stock_chart_data(notified_by_month)
    months = notified_by_month.to_a.reverse
    { labels: months.map { |month, _| month.strftime('%m/%Y') }.to_json, values: months.map(&:last).to_json }
  end

  def back_in_stock_currency(value)
    number_to_currency(value, unit: 'R$', separator: ',', delimiter: '.', format: '%u %n')
  end

  def back_in_stock_phone(phone)
    return '—' if phone.blank?
    return phone unless phone.start_with?('+55')

    number_to_phone(phone.delete_prefix('+55'), area_code: true, pattern: /(\d{2})(\d{4,5})(\d{4})$/)
  end

  def back_in_stock_product_url(client, handle)
    "#{client.storefront_url}/products/#{handle}"
  end
end
