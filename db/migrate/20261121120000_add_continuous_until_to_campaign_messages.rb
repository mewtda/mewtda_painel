# Mensagem contínua: até esta data/hora, quem entra no segmento também recebe a mensagem (uma vez só).
class AddContinuousUntilToCampaignMessages < ActiveRecord::Migration[7.2]
  def change
    add_column :campaign_messages, :continuous_until, :datetime
  end
end
