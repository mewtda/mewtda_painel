class AddAutoReplyToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :auto_reply_enabled, :boolean, default: false, null: false
    add_column :clients, :openai_api_key, :text
    add_column :clients, :openai_model, :string
    add_column :clients, :auto_reply_instructions, :text
  end
end
