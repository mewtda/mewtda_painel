module ProfilesHelper
  PROFILE_ICONS = { Profile::ADMIN => 'fa-user-shield', Profile::USER => 'fa-user', Profile::AFFILIATE => 'fa-handshake' }.freeze

  def profile_icon(profile)
    tag.i(class: "fa-solid #{PROFILE_ICONS.fetch(profile.id, 'fa-id-badge')}")
  end
end
