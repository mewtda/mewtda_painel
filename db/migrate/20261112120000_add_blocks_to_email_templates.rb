class AddBlocksToEmailTemplates < ActiveRecord::Migration[7.2]
  def change
    add_column :email_templates, :blocks, :jsonb, null: false, default: []
    add_column :email_templates, :design, :jsonb, null: false, default: {}

    # O conteúdo agora vive nos blocos; os campos antigos ficam só como legado
    # (templates criados antes do editor por blocos são convertidos na leitura).
    change_column_null :email_templates, :heading, true
    change_column_null :email_templates, :body, true
    change_column_null :email_templates, :button_text, true
  end
end
