# Segmento de clientes de uma loja: dinâmico (regras recalculadas sempre) ou
# lista estática (clientes escolhidos a dedo).
class Segment < ApplicationRecord
  KINDS = { 'dynamic' => 'Segmento', 'static' => 'Lista' }.freeze

  belongs_to :client
  has_many :segment_memberships, dependent: :delete_all
  has_many :customers, through: :segment_memberships

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 500 }
  validates :kind, inclusion: { in: KINDS.keys }
  validate :dynamic_needs_rules

  def rules=(value)
    super(Segments::Rules.sanitize(value))
  end

  def rules_json=(value)
    self.rules = value
  end

  def dynamic? = kind == 'dynamic'
  def static? = kind == 'static'
  def kind_label = KINDS.fetch(kind)

  # Perfis (CustomerProfile) da loja que estão no segmento.
  def profiles(depth: 0, exclude_ids: [id].compact)
    if static?
      ids = segment_memberships.pluck(:customer_id)
      CustomerProfile.where(client_id:).where(
        'customer_profiles.customer_id IN (:ids) OR customer_profiles.merged_customer_ids && ARRAY[:ids]::bigint[]',
        ids: ids.presence || [0]
      )
    else
      Segments::Rules.new(client, rules, depth:, exclude_ids:).scope
    end
  end

  def customer_ids_sql(depth: 0, exclude_ids: [id].compact)
    profiles(depth:, exclude_ids:).select(:customer_id).to_sql
  end

  def duplicate!
    copy = client.segments.create!(name: "Cópia de #{name}".first(120), description:, kind:, rules:)
    if static?
      now = Time.current
      rows = segment_memberships.pluck(:customer_id).map do |customer_id|
        { segment_id: copy.id, customer_id:, created_at: now, updated_at: now }
      end
      SegmentMembership.insert_all(rows) if rows.any?
    end
    copy.tap(&:recount!)
  end

  def recount!
    scope = profiles
    update_columns(customers_count: scope.count, subscribed_count: scope.where(email_marketing_state: 'subscribed').count,
                   counted_at: Time.current)
  end

  private

  def dynamic_needs_rules
    errors.add(:base, 'Adicione pelo menos uma condição ao segmento.') if dynamic? && Array(rules['groups']).empty?
  end
end
