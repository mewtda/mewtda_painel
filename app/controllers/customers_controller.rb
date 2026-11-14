# Clientes: base de compradores da loja com números de compra e
# perfil RFM (customer_profiles), filtros por segmento/RFM e matriz RFM.
class CustomersController < ApplicationController
  include ClientScoped
  include EnsuresCustomerProfiles

  PER_PAGE = 50
  SORTS = {
    'name' => 'customer_profiles.name',
    'last_order_at' => 'customer_profiles.last_order_at',
    'orders_count' => 'customer_profiles.orders_count',
    'avg_ticket' => 'customer_profiles.avg_ticket',
    'total_spent' => 'customer_profiles.total_spent',
    'rfm' => 'customer_profiles.r_score'
  }.freeze

  before_action :authenticate_user!
  before_action :set_client
  before_action :require_client!
  before_action :ensure_profiles, only: %i[index rfm export_xlsx]
  before_action :set_filtered_scope, only: %i[index export_xlsx]

  def index
    @summary = summary(@client.customer_profiles)
    @sort, @direction = sort_params
    @profiles = @scope.order(Arel.sql("#{SORTS.fetch(@sort)} #{@direction} NULLS LAST, customer_profiles.id"))
                      .paginate(page: params[:page], per_page: PER_PAGE)
    @filtered_count = @profiles.total_entries
    @lists = @client.segments.where(kind: 'static').order(:name)
    @segments = @client.segments.order(:name)
    @popup_emails = popup_emails
  end

  def rfm
    profiles = @client.customer_profiles
    @total = profiles.count
    @counts = profiles.group(:rfm_segment).count
    @stats = profiles.group(:rfm_segment)
                     .pluck(:rfm_segment, Arel.sql('AVG(total_spent)'), Arel.sql('AVG(orders_count)'),
                            Arel.sql('SUM(total_spent)'), Arel.sql('AVG(CURRENT_DATE - last_order_at::date)'))
                     .to_h { |seg, *values| [seg, values] }
    @selected = params[:perfil].presence_in(CustomerProfile::RFM_SEGMENTS.keys)
  end

  # Ação em massa: adiciona os clientes selecionados (ou todo o filtro) a uma lista.
  def add_to_list
    list = target_list
    return redirect_back(fallback_location: customers_path, alert: 'Escolha ou dê nome a uma lista.') unless list

    ids = params[:all_filtered] == '1' ? filtered_customer_ids : selected_customer_ids
    now = Time.current
    rows = ids.map { |id| { segment_id: list.id, customer_id: id, created_at: now, updated_at: now } }
    SegmentMembership.insert_all(rows, unique_by: %i[segment_id customer_id]) if rows.any?
    list.recount!
    redirect_back fallback_location: customers_path,
                  notice: "#{helpers.pluralize(ids.size, 'cliente adicionado', plural: 'clientes adicionados')} à lista #{list.name}."
  end

  def details
    profile = @client.customer_profiles.find_by!(customer_id: params[:id])
    customer = profile.customer
    orders = Order.where(client_id: @client.id, customer_id: profile.customer_ids).includes(order_items: :product)
                  .order(shopify_creation_date: :desc)

    render json: {
      shopify_store: @client.shopify_admin_handle,
      customer: {
        id: customer.id, name: profile.name || 'Sem nome', email: profile.email, phone: profile.phone,
        shopify_id: customer.shopify_customer_id, city: [profile.city, profile.state].compact.join(' / ').presence,
        created_at: customer.created_at.strftime('%d/%m/%Y %H:%M'),
        rfm: profile.rfm_label, rfm_color: profile.rfm_color,
        rfm_hint: CustomerProfile::RFM_SEGMENTS.dig(profile.rfm_segment, :hint),
        orders_count: profile.orders_count, total_spent: profile.total_spent.to_f, avg_ticket: profile.avg_ticket.to_f,
        first_order_at: profile.first_order_at&.strftime('%d/%m/%Y'), last_order_at: profile.last_order_at&.strftime('%d/%m/%Y'),
        days_since: profile.days_since_last_order,
        lists: customer.segment_memberships.joins(:segment).where(segments: { client_id: @client.id }).pluck('segments.name')
      },
      orders: orders.map { |order| order_json(order) }
    }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Cliente não encontrado' }, status: :not_found
  end

  def export_xlsx
    sheet = Spreadsheets::Customers.new(@scope)
    send_data sheet.to_xlsx, filename: sheet.filename, type: sheet.content_type
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_filtered_scope
    @segment = @client.segments.find_by(id: params[:segment_id]) if params[:segment_id].present?
    scope = @segment ? @segment.profiles : @client.customer_profiles
    scope = scope.search(params[:q])
    @rfm_filter = Array(params[:rfm]).compact_blank & CustomerProfile::RFM_SEGMENTS.keys
    scope = scope.where(rfm_segment: @rfm_filter) if @rfm_filter.any?
    @scope = scope
  end

  def sort_params
    sort = params[:sort].presence_in(SORTS.keys) || 'last_order_at'
    direction = params[:dir] == 'asc' ? 'ASC' : 'DESC'
    [sort, direction]
  end

  def summary(profiles)
    total, repeat, spent, orders = profiles.pick(Arel.sql('COUNT(*)'), Arel.sql('COUNT(*) FILTER (WHERE orders_count > 1)'),
                                                 Arel.sql('COALESCE(SUM(total_spent), 0)'), Arel.sql('COALESCE(SUM(orders_count), 0)'))
    total = total.to_i
    {
      total:, repeat_rate: total.zero? ? 0 : (repeat.to_f / total * 100).round(1),
      ltv: total.zero? ? 0 : spent.to_f / total, avg_ticket: orders.to_i.zero? ? 0 : spent.to_f / orders.to_i,
      active: profiles.where(rfm_segment: CustomerProfile::ACTIVE_SEGMENTS).count
    }
  end

  def popup_emails
    popup = Popup.find_by(client_id: @client.id)
    return Set.new unless popup

    popup.popup_submissions.pluck(:email).filter_map { |email| email&.downcase }.to_set
  end

  def target_list
    return @client.segments.find_by(id: params[:list_id], kind: 'static') if params[:new_list_name].blank?

    list = @client.segments.create(name: params[:new_list_name].strip, kind: 'static')
    list if list.persisted?
  end

  def selected_customer_ids
    @client.customer_profiles.where(customer_id: Array(params[:customer_ids])).pluck(:customer_id)
  end

  def filtered_customer_ids
    set_filtered_scope
    @scope.pluck(:customer_id)
  end

  def order_json(order)
    items = order.order_items
    {
      number: order.shopify_order_number, shopify_id: order.shopify_order_id,
      date: order.shopify_creation_date&.strftime('%d/%m/%Y %H:%M'),
      total: order.total_price.to_f, items_count: items.size, coupon: order.discount_code.presence,
      items: items.map do |i|
        { name: i.product&.shopify_product_name || i.sku, sku: i.sku, qty: i.quantity, price: i.price.to_f,
          image: i.product&.image_url }
      end
    }
  end
end
