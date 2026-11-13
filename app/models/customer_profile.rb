# Um cliente visto por uma loja: números de compra e perfil RFM, recalculados
# a partir dos pedidos por Customers::RefreshProfiles.
class CustomerProfile < ApplicationRecord
  # Ordem = ordem de exibição (dos melhores para os piores).
  RFM_SEGMENTS = {
    'champion' => { label: 'Campeão', color: '#7c3aed', hint: 'Compram muito, com frequência e recentemente.' },
    'loyal' => { label: 'Fidelizado', color: '#10b981', hint: 'Compram com frequência. Ótimos para programas de fidelidade.' },
    'potential_loyal' => { label: 'Possível leal', color: '#0ea5e9', hint: 'Compraram recentemente mais de uma vez. Dá para fidelizar.' },
    'new' => { label: 'Novo', color: '#6366f1', hint: 'Fizeram a primeira compra há pouco tempo.' },
    'promising' => { label: 'Promissor', color: '#3b82f6', hint: 'Compra recente, mas única. Incentive a segunda compra.' },
    'need_attention' => { label: 'Precisa de atenção', color: '#a855f7', hint: 'Medianos em tudo e começando a esfriar.' },
    'about_to_sleep' => { label: 'Quase hibernando', color: '#8b5cf6', hint: 'Pouca frequência e sem comprar há um tempo.' },
    'cant_lose' => { label: 'Não pode perder', color: '#f43f5e', hint: 'Já foram ótimos clientes e sumiram. Prioridade de reconquista.' },
    'at_risk' => { label: 'Em risco', color: '#f59e0b', hint: 'Compravam com frequência, mas não voltam há bastante tempo.' },
    'hibernating' => { label: 'Hibernando', color: '#94a3b8', hint: 'Compraram pouco e há muito tempo.' }
  }.freeze

  # Grade RFM: recência (R, 5 = mais recente) x frequência (F, 1..5 compras).
  RFM_GRID = {
    5 => %w[new potential_loyal potential_loyal champion champion],
    4 => %w[promising potential_loyal potential_loyal loyal champion],
    3 => %w[about_to_sleep about_to_sleep need_attention loyal loyal],
    2 => %w[hibernating about_to_sleep at_risk at_risk cant_lose],
    1 => %w[hibernating hibernating at_risk at_risk cant_lose]
  }.freeze

  ACTIVE_SEGMENTS = %w[champion loyal potential_loyal new promising].freeze
  INACTIVE_SEGMENTS = %w[need_attention about_to_sleep cant_lose at_risk hibernating].freeze

  belongs_to :client
  belongs_to :customer

  scope :search, lambda { |term|
    next all if term.blank?

    like = "%#{sanitize_sql_like(term.strip)}%"
    digits = term.gsub(/\D/, '')
    clause = 'customer_profiles.name ILIKE :like OR customer_profiles.email ILIKE :like'
    clause += " OR regexp_replace(customer_profiles.phone, '\\D', '', 'g') LIKE :digits" if digits.length >= 4
    where(clause, like:, digits: "%#{digits}%")
  }

  def self.segment_for(r_score, f_score)
    RFM_GRID.dig(r_score.to_i.clamp(1, 5), f_score.to_i.clamp(1, 5) - 1)
  end

  def self.rfm_label(key) = RFM_SEGMENTS.dig(key, :label)

  def rfm_label = self.class.rfm_label(rfm_segment)
  def rfm_color = RFM_SEGMENTS.dig(rfm_segment, :color)

  def days_since_last_order
    (Time.zone.today - last_order_at.to_date).to_i if last_order_at
  end
end
