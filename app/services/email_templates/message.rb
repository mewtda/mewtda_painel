module EmailTemplates
  class Message
    VARIABLE = /\{(\w+)\}/
    DEFAULT_ACCENT_COLOR = '#7c3aed'.freeze
    HEX_COLOR = /\A#[0-9a-fA-F]{6}\z/
    SAFE_URL = %r{\Ahttps?://}

    attr_reader :image_url, :image_bottom_url, :logo_url, :unsubscribe_url, :product

    delegate :layout, :coupon_code, to: :@template

    def initialize(template, variables: {}, product: nil, **urls)
      @template = template
      @variables = variables.stringify_keys
      @product = product
      @image_url = urls[:image_url]
      @image_bottom_url = urls[:image_bottom_url]
      @logo_url = urls[:logo_url]
      @button_url = urls[:button_url].presence || template.button_url
      @unsubscribe_url = urls[:unsubscribe_url]
    end

    def subject
      interpolate(@template.subject)
    end

    def heading
      interpolate(@template.heading)
    end

    def body
      interpolate(@template.body)
    end

    def button_text
      interpolate(@template.button_text)
    end

    def button_url
      @button_url if @button_url.to_s.match?(SAFE_URL)
    end

    def store_name
      @variables['loja']
    end

    def accent_color
      @template.accent_color.to_s.match?(HEX_COLOR) ? @template.accent_color : DEFAULT_ACCENT_COLOR
    end

    def side_image?
      layout.in?(%w[image_left image_right]) && image_url.present?
    end

    def top_image?
      layout.in?(%w[image_top image_top_bottom]) && image_url.present?
    end

    def bottom_image?
      layout == 'image_top_bottom' && image_bottom_url.present?
    end

    def html
      ApplicationController.render(partial: 'email_templates/email', locals: { message: self })
    end

    def text
      parts = [store_name, heading, product_summary, body, coupon_code, button_line, unsubscribe_line]
      parts.compact_blank.join("\n\n")
    end

    private

    def product_summary
      return unless product

      [product[:title], ("Variação: #{product[:variant]}" if product[:variant].present?)].compact.join("\n")
    end

    def button_line
      "#{button_text}: #{button_url}" if button_url
    end

    def unsubscribe_line
      "Não quero mais receber estes e-mails: #{unsubscribe_url}" if unsubscribe_url
    end

    def interpolate(text)
      text.to_s.gsub(VARIABLE) { @variables.fetch(Regexp.last_match(1), Regexp.last_match(0)) }
    end
  end
end
