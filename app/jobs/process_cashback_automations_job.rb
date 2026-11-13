class ProcessCashbackAutomationsJob < ApplicationJob
  queue_as :default

  def perform(client_id = nil)
    scope = client_id ? Client.where(id: client_id) : Client.where(active: true)

    scope.find_each do |client|
      process_client(client)
    rescue StandardError => e
      Rails.logger.error "[ProcessCashbackAutomations] Erro: #{e.message}"
    end
  end

  private

  def process_client(client)
    running_automations = client.automations.running
    return if running_automations.empty?

    unless client.shopify_shop_url.present? && client.shopify_access_token.present?
      return
    end

    shopify_service = Shopify::DiscountService.new(client)

    orders = Order.joins(:customer)
                  .where(customers: { client_id: client.id })
                  .order(created_at: :desc)

    orders.find_each do |order|
      running_automations.each do |automation|
        process_order_for_automation(automation, order, shopify_service)
      rescue StandardError => e
        Rails.logger.error "[ProcessCashbackAutomations] Erro: #{e.message}"
      end
    end
  end

  def process_order_for_automation(automation, order, shopify_service)
    customer = order.customer
    return unless customer.present?

    case automation.kind
    when 'cashback'
      return if AutomationAction.exists?(automation_id: automation.id, order_id: order.id, customer_id: customer.id,
                                       status: :sent)

      process_cashback(automation, order, customer, shopify_service)
    when 'cashback_expiration'
      return if AutomationAction.exists?(automation_id: automation.id, order_id: order.id, customer_id: customer.id,
                                       status: :sent)

      process_cashback_expiration(automation, order, customer, shopify_service)
    when 'shipping_tracking'
      # Reenvia várias vezes (limitado por automation.max_sends), então não usa o
      # mesmo guard de "já enviado uma vez" das campanhas de cashback.
      process_shipping_tracking(automation, order, customer)
    end
  end

  def process_cashback(automation, order, customer, shopify_service)
    purchase_date  = (order.shopify_creation_date || order.created_at).to_date
    scheduled_date = purchase_date + automation.days_after_purchase.days

    return if Date.current < scheduled_date
    return if Date.current > scheduled_date + 3.days

    discount = shopify_service.find_by_order(order)
    return unless discount.present?

    if discount[:is_expired]
      AutomationAction.create!(
        automation: automation,
        customer: customer,
        order: order,
        kind: automation.kind,
        status: :cancelled,
        scheduled_for: scheduled_date.to_datetime
      )
      return
    end

    return if AutomationAction.exists?(automation_id: automation.id, order_id: order.id, customer_id: customer.id,
                                     status: :pending)

    action = AutomationAction.create!(
      automation: automation,
      customer: customer,
      order: order,
      kind: automation.kind,
      status: :pending,
      scheduled_for: scheduled_date.to_datetime
    )

    SendAutomationNotificationJob.perform_later(action.id,
                                              { code: discount[:code], discount_value: discount[:discount_value] })
  end

  def process_cashback_expiration(automation, order, customer, shopify_service)
    discount = shopify_service.find_by_order(order)
    return unless discount.present?
    return unless discount[:ends_at].present?

    expiration_date = discount[:ends_at].to_date
    send_date       = expiration_date - automation.days_after_purchase.days

    return if Date.current < send_date

    if discount[:is_expired] || Date.current > expiration_date
      AutomationAction.create!(
        automation: automation,
        customer: customer,
        order: order,
        kind: automation.kind,
        status: :cancelled,
        scheduled_for: send_date.to_datetime
      )
      return
    end

    return if AutomationAction.exists?(automation_id: automation.id, order_id: order.id, customer_id: customer.id,
                                     status: :pending)

    action = AutomationAction.create!(
      automation: automation,
      customer: customer,
      order: order,
      kind: automation.kind,
      status: :pending,
      scheduled_for: send_date.to_datetime
    )

    SendAutomationNotificationJob.perform_later(action.id,
                                              { code: discount[:code], discount_value: discount[:discount_value],
                                                ends_at: discount[:ends_at] })
  end

  # Só considera pedidos com código de rastreio preenchido, fulfilled a partir da
  # "Data início" da campanha, e respeita o limite/intervalo configurados nela.
  def process_shipping_tracking(automation, order, customer)
    return if order.tracking_number.blank?
    return if order.fulfilled_at.blank?
    return if order.fulfilled_at.to_date < automation.start_date

    sent_actions = AutomationAction.where(automation_id: automation.id, order_id: order.id, customer_id: customer.id,
                                        status: :sent)
    return if sent_actions.count >= automation.max_sends

    last_sent_at = sent_actions.maximum(:notified_at)
    return if last_sent_at.present? && Date.current < (last_sent_at.to_date + automation.interval_days.days)

    action = AutomationAction.create!(
      automation: automation,
      customer: customer,
      order: order,
      kind: automation.kind,
      status: :pending
    )

    SendAutomationNotificationJob.perform_later(action.id, {})
  end
end
