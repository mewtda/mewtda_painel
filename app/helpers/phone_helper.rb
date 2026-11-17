module PhoneHelper
  def format_phone(phone)
    return '—' if phone.blank?

    digits = phone.to_s.delete('^0-9')
    foreign = phone.to_s.strip.start_with?('+') && !digits.start_with?('55')
    digits = digits.delete_prefix('55') if digits.length > 11 && digits.start_with?('55')
    return phone if foreign || !digits.length.in?([10, 11])

    "(#{digits[0, 2]}) #{digits[2...-4]}-#{digits[-4..]}"
  end

  def phone_link(phone)
    return tag.span('—', class: 'cx-muted') if phone.blank?

    link_to "tel:#{phone}", class: 'phone-link' do
      safe_join([tag.i(class: 'fa-solid fa-phone'), format_phone(phone)], ' ')
    end
  end
end
