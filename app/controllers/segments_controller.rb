class SegmentsController < ApplicationController
  include ClientScoped
  include EnsuresCustomerProfiles

  before_action :authenticate_user!
  before_action :set_client
  before_action :require_client!
  before_action :ensure_profiles, only: %i[index templates new edit]
  before_action :set_segment, only: %i[edit update destroy recount duplicate]
  before_action :set_product_options, only: %i[new edit create update]

  SORTS = %w[name kind customers_count updated_at].freeze

  def index
    @sort = params[:sort].presence_in(SORTS) || 'updated_at'
    @direction = params[:dir] == 'asc' ? 'asc' : 'desc'
    @segments = @client.segments.order(@sort => @direction, id: :desc)
    @segments = @segments.where('name ILIKE ?', "%#{Segment.sanitize_sql_like(params[:q])}%") if params[:q].present?
    @base_total = @client.customer_profiles.count
  end

  # Galeria de segmentos sugeridos.
  def templates
    @templates = Segments::Templates.all
  end

  def new
    template = Segments::Templates.all[params[:template]] || rfm_template
    kind = params[:kind] == 'static' ? 'static' : 'dynamic'
    @segment = @client.segments.new(kind:, name: template&.dig(:name), description: template&.dig(:description),
                                    rules: template&.dig(:rules) || {})
  end

  def create
    @segment = @client.segments.new(segment_params)
    if @segment.save
      @segment.recount!
      redirect_to customers_path(segment_id: @segment.id), notice: "#{@segment.kind_label} \"#{@segment.name}\" criado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @segment.update(segment_params.except(:kind))
      @segment.recount!
      redirect_to segments_path, notice: "#{@segment.kind_label} atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @segment.destroy
    redirect_to segments_path, notice: "#{@segment.kind_label} \"#{@segment.name}\" excluído."
  end

  def recount
    @segment.recount!
    redirect_to segments_path
  end

  def duplicate
    copy = @segment.duplicate!
    redirect_to edit_segment_path(copy), notice: "#{copy.kind_label} duplicado. Ajuste o nome e as regras."
  end

  # Contagem ao vivo no construtor ("Resumo do seu segmento").
  def preview
    segment = @client.segments.find_by(id: params[:id]) || @client.segments.new
    segment.rules = params[:rules_json]
    rules = Segments::Rules.new(@client, segment.rules, exclude_ids: [segment.id].compact)
    count = rules.empty? ? 0 : rules.scope.count
    total = @client.customer_profiles.count
    sample = rules.empty? ? [] : rules.scope.order(total_spent: :desc).limit(5).pluck(:name, :total_spent)
    subscribed = rules.empty? ? 0 : rules.scope.where(email_marketing_state: 'subscribed').count
    render json: { count:, subscribed:, total:, percent: total.zero? ? 0 : (count * 100.0 / total).round(1),
                   sample: sample.map { |name, spent| { name:, spent: spent.to_f } } }
  end

  private

  def set_product_options
    options = Segments::ProductOptions.new(@client)
    @product_options = { categories: options.categories, sizes: options.sizes }
  end

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end

  def set_segment
    @segment = @client.segments.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to segments_path, alert: 'Segmento não encontrado.'
  end

  def rfm_template
    key = params[:rfm].presence_in(CustomerProfile::RFM_SEGMENTS.keys)
    return unless key

    { name: "RFM: #{CustomerProfile.rfm_label(key)}", description: CustomerProfile::RFM_SEGMENTS.dig(key, :hint),
      rules: Segments::Templates.rules(Segments::Templates.cond('rfm_segment', 'in', [key])) }
  end

  def segment_params
    params.require(:segment).permit(:name, :description, :kind, :rules_json)
  end
end
