module AvatarHelper
  AVATAR_TONES = 8

  def avatar_initials(name, count: 2)
    name.to_s.split.first(count).filter_map { |word| word[0] }.join.upcase.presence || '?'
  end

  def avatar_tone(name)
    Zlib.crc32(name.to_s.strip.downcase) % AVATAR_TONES
  end

  def avatar_tag(name, initials: 2, **options)
    classes = ['avatar', "avatar--tone-#{avatar_tone(name)}", options.delete(:class)].compact.join(' ')
    tag.span(avatar_initials(name, count: initials), class: classes, **options)
  end
end
