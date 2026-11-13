class OrdersController < ApplicationController
  before_action :load_form_references, only: [:index]
  before_action :set_filter_scope, only: [:index, :export_xlsx]

  def index
    @orders = @orders_scope.includes(:customer, order_items: :product)
                           .order(shopify_creation_date: :desc)
                           .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))
    active_orders = @orders_scope.not_cancelled
    @filtered_count = active_orders.count
    @filtered_total = active_orders.sum(:total_price)
  end

  def details
    order    = orders_scope.includes(:customer, order_items: :product).find(params[:id])
    customer = order.customer
    items    = order.order_items

    render json: {
      order: {
        number: order.shopify_order_number,
        shopify_id: order.shopify_order_id,
        date: order.shopify_creation_date&.strftime('%d/%m/%Y às %H:%M'),
        total: order.paid_total.to_f.round(2),
        tags: order.tags,
        kinds: order.kinds
      },
      customer: {
        name: customer ? [[customer.first_name, customer.last_name].compact.join(' ').presence,
                          customer.name].compact.first : nil,
        email: customer&.email,
        phone: customer&.phone
      },
      items: items.map { |i|
        product = i.product
        {
          name: product&.shopify_product_name || i.try(:sku) || "Item ##{i.id}",
          sku: i.sku.to_s,
          qty: i.quantity.to_i,
          price: i.price.to_f,
          subtotal: (i.price.to_f * i.quantity.to_i).round(2),
          image: product&.image_url.to_s,
          option1: product&.option1,
          option2: product&.option2,
          option3: product&.option3
        }
      }
    }
  end

  def export_xlsx
    orders = @orders_scope
             .includes(:customer, order_items: :product)
             .order(shopify_creation_date: :desc)

    workbook  = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Pedidos'

    headers = ['ID', 'Nº Pedido', 'ID Shopify', 'Cliente', 'Telefone', 'Itens', 'Total pago (R$)', 'Data', 'Frete (R$)', 'Desconto (R$)']
    headers.each_with_index { |h, i| worksheet.add_cell(0, i, h) }

    row = 1
    orders.each do |o|
      customer  = o.customer
      full_name = customer ? [[customer.first_name, customer.last_name].compact.join(' ').presence,
                              customer.name].compact.first.to_s : ''
      items     = o.order_items

      worksheet.add_cell(row, 0, o.id)
      worksheet.add_cell(row, 1, o.shopify_order_number.to_s)
      worksheet.add_cell(row, 2, o.shopify_order_id.to_s)
      worksheet.add_cell(row, 3, full_name)
      worksheet.add_cell(row, 4, customer&.phone.to_s)
      worksheet.add_cell(row, 5, items.size)
      worksheet.add_cell(row, 6, o.paid_total.to_f.round(2))
      worksheet.add_cell(row, 7, o.shopify_creation_date&.strftime('%d/%m/%Y %H:%M').to_s)
      worksheet.add_cell(row, 8, o.total_shipping_price.to_f.round(2))
      worksheet.add_cell(row, 9, o.total_discounts.to_f.round(2))
      row += 1
    end

    file_path = Rails.root.join('tmp', "orders_#{SecureRandom.hex(4)}.xlsx")
    workbook.write(file_path.to_s)

    send_file file_path,
              filename: "pedidos_#{Time.current.strftime('%Y%m%d_%H%M')}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              disposition: 'attachment'
  end

  private

  def current_client_id
    if current_user.admin?
      session[:selected_client_id] || current_user.client_id
    else
      current_user.client_id
    end
  end

  def orders_scope
    Order.where(client_id: current_client_id)
  end

  def set_filter_scope
    @orders_scope = orders_scope # <-- Agora usa orders_scope ao invés de Order.all
    @orders_scope = @orders_scope.where(kinds: params[:kinds]) if params[:kinds].present?
    @orders_scope = @orders_scope.where(staff_name: params[:staff_name]) if params[:staff_name].present?

    if params[:search].present?
      @orders_scope = @orders_scope.where('shopify_order_number ILIKE ?', "%#{params[:search]}%")
    end

    if params[:date_from].present?
      @orders_scope = @orders_scope.where('shopify_creation_date >= ?', params[:date_from].to_date)
    end

    if params[:date_to].present?
      @orders_scope = @orders_scope.where('shopify_creation_date <= ?', params[:date_to].to_date.end_of_day)
    end
  end

  def load_form_references
    @kinds       = orders_scope.distinct.pluck(:kinds).compact.sort       # <-- Também filtrado por client
    @staff_names = orders_scope.distinct.pluck(:staff_name).compact.sort  # <-- Também filtrado por client
  end
end
