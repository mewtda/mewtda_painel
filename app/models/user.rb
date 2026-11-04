class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :profile, optional: true
  belongs_to :client, optional: true
  has_many :whatsapp_memberships, class_name: 'Whatsapp::Membership', dependent: :delete_all

  def admin?
    profile_id == 1
  end
end
