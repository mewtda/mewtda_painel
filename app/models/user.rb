class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :profile, optional: true
  belongs_to :client, optional: true

  def admin?
    profile_id == 1
  end
end
