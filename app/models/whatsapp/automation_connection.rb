module Whatsapp
  # Número responsável por uma automação; as mensagens da automação alternam entre eles.
  class AutomationConnection < ApplicationRecord
    self.table_name = 'whatsapp_automation_connections'

    belongs_to :automation
    belongs_to :connection, class_name: 'Whatsapp::Connection'
    validates :connection_id, uniqueness: { scope: :automation_id }
    validate do
      errors.add(:connection, 'número de outro cliente') if automation && connection && connection.client_id != automation.client_id
    end

    after_create do
      automation.update_column(:evolution_started_at, Time.current) if automation.evolution_started_at.nil?
    end
  end
end
