class AddEmailTemplateToEmailSuppressions < ActiveRecord::Migration[7.2]
  def change
    add_reference :email_suppressions, :email_template, foreign_key: { on_delete: :nullify }, null: true
  end
end
