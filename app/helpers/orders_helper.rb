module OrdersHelper
  def order_money(value)
    "R$ #{number_with_precision(value, precision: 2, delimiter: '.', separator: ',')}"
  end

  def order_discount_label(order)
    order.total_discounts.to_f.positive? ? "- #{order_money(order.total_discounts)}" : '—'
  end

  def order_coupon_label(order)
    order.discount_code.presence || '—'
  end

  def order_shipping_label(order)
    order.total_shipping_price.to_f.positive? ? order_money(order.total_shipping_price) : 'Grátis'
  end
end
