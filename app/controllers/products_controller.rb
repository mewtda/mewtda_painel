class ProductsController < ApplicationController
  before_action :set_client_scope
  before_action :load_form_references, only: [:index], if: -> { params[:aba] == 'produtos' }
  before_action :set_filter_scope, only: [:index, :export_xlsx]

  TABS = %w[dashboard produtos].freeze
  CURVE_FILTERS = { 'A' => 'Curva A', 'B' => 'Curva B', 'C' => 'Curva C', 'sem_venda' => 'Sem venda no período' }.freeze

  def index
    @tab = params[:aba].presence_in(TABS) || 'dashboard'
    @abc = abc
    return if @tab == 'dashboard'

    @products = @products_scope
                .order(created_at: :desc)
                .paginate(page: params[:page], per_page: params_per_page(params[:per_page]))
  end

  def export_xlsx
    products = @products_scope.order(created_at: :desc)

    workbook  = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Produtos'

    headers = ['ID', 'SKU', 'Nome', 'Fornecedor', 'Cor/Variação 1', 'Tamanho/Variação 2', 'Variação 3', 'Preço (R$)',
               'Custo (R$)', 'ID Shopify', 'Criado em']
    headers.each_with_index { |h, i| worksheet.add_cell(0, i, h) }

    row = 1
    products.each do |p|
      worksheet.add_cell(row, 0,  p.id)
      worksheet.add_cell(row, 1,  p.sku.to_s)
      worksheet.add_cell(row, 2,  p.shopify_product_name.to_s)
      worksheet.add_cell(row, 3,  p.vendor.to_s)
      worksheet.add_cell(row, 4,  p.option1.to_s)
      worksheet.add_cell(row, 5,  p.option2.to_s)
      worksheet.add_cell(row, 6,  p.option3.to_s)
      worksheet.add_cell(row, 7,  p.price.to_f.round(2))
      worksheet.add_cell(row, 8,  p.cost.to_f.round(2))
      worksheet.add_cell(row, 9,  p.shopify_product_id.to_s)
      worksheet.add_cell(row, 10, p.created_at.strftime('%d/%m/%Y %H:%M'))
      row += 1
    end

    file_path = Rails.root.join('tmp', "products_#{SecureRandom.hex(4)}.xlsx")
    workbook.write(file_path.to_s)

    send_file file_path,
              filename: "produtos_#{Time.current.strftime('%Y%m%d_%H%M')}.xlsx",
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

  def set_client_scope
    @client_id = current_client_id
    @client = Client.find_by(id: @client_id)
  end

  # Curva ABC do período escolhido (p/de/ate); a mesma do dashboard, para o filtro e a coluna Curva.
  def abc
    return unless @client

    @abc ||= Sales::ProductAbc.new(client: @client, preset: params[:p], from: params[:de], to: params[:ate])
  end

  # Curva A/B/C = produtos da Shopify com essa curva; "sem venda" = produtos que não venderam no período.
  def filter_by_curve(scope)
    curve = params[:curva].presence_in(CURVE_FILTERS.keys)
    return scope unless curve && abc

    curves = abc.curve_by_product_id.reject { |key, _| key.start_with?('sku:') }
    return scope.where.not(shopify_product_id: curves.keys).or(scope.where(shopify_product_id: nil)) if curve == 'sem_venda'

    scope.where(shopify_product_id: curves.select { |_, value| value == curve }.keys)
  end

  def set_filter_scope
    @products_scope = Product.where(client_id: @client_id)
    @products_scope = @products_scope.where(vendor: params[:vendor]) if params[:vendor].present?
    @products_scope = @products_scope.where(option1: params[:option1]) if params[:option1].present?
    @products_scope = @products_scope.where(option2: params[:option2]) if params[:option2].present?

    if params[:search].present?
      term = "%#{Product.sanitize_sql_like(params[:search].to_s.strip)}%"
      @products_scope = @products_scope.where('shopify_product_name ILIKE :term OR sku ILIKE :term', term:)
    end
    @products_scope = filter_by_curve(@products_scope)
  end

  def load_form_references
    @vendors  = Product.where(client_id: @client_id).distinct.pluck(:vendor).compact.sort
    @option1s = Product.where(client_id: @client_id).distinct.pluck(:option1).compact.sort
    @option2s = Product.where(client_id: @client_id).distinct.pluck(:option2).compact.sort
  end
end
