module Whatsapp
  class Membership < ApplicationRecord
    belongs_to :connection
    belongs_to :user
    validates :user_id, uniqueness: { scope: :connection_id }
    validate do
      errors.add(:user, 'usuário de outro cliente') if user && connection && user.client_id != connection.client_id
    end
  end
end
