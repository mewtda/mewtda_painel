# A Z-API foi removida: todo cliente passa a usar a Evolution Mewtda.
# As colunas zapi_* ficam no banco (sem uso) para não apagar credenciais.
class AllClientsUseEvolution < ActiveRecord::Migration[7.2]
  def up
    change_column_default :clients, :whatsapp_provider, from: 'zapi', to: 'evolution'
    execute "UPDATE clients SET whatsapp_provider = 'evolution'"
  end

  def down
    change_column_default :clients, :whatsapp_provider, from: 'evolution', to: 'zapi'
  end
end
