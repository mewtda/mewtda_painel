class AddSalesChannelsToClients < ActiveRecord::Migration[7.2]
  def change
    # Canais de venda da Shopify considerados nos relatórios (vazio = todos).
    add_column :clients, :sales_channels, :string, array: true, default: [], null: false
  end
end
