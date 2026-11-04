class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  belongs_to :profile, optional: true
  belongs_to :client, optional: true
  has_many :whatsapp_memberships, class_name: 'Whatsapp::Membership', dependent: :delete_all
  has_many :whatsapp_reads, class_name: 'Whatsapp::Read', dependent: :delete_all
  has_many :whatsapp_messages, class_name: 'Whatsapp::Message', dependent: :nullify

  def admin?
    profile_id == 1
  end
end
