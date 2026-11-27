class CreateCustomAutomationSettings < ActiveRecord::Migration[7.2]
  # Configuração de cada rotina personalizada por cliente (ex.: quem recebe o relatório semanal da Fernanda
  # Farah) e quando ela rodou pela última vez.
  def change
    create_table :custom_automation_settings do |t|
      t.references :client, null: false, foreign_key: true
      t.string :kind, null: false
      t.jsonb :settings, null: false, default: {}
      t.datetime :last_run_at
      t.timestamps
    end
    add_index :custom_automation_settings, %i[client_id kind], unique: true
  end
end
