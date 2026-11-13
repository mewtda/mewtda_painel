module EmailTemplates
  # Converte um template do editor antigo (heading/body/layout fixos) em
  # blocos equivalentes, pra continuar enviando igual e abrir no editor novo.
  class LegacyBlocks
    def initialize(template)
      @template = template
    end

    def call
      return [] if template.heading.blank? && template.body.blank?

      blocks = [{ 'type' => 'logo' }] + content
      Blocks.sanitize(blocks)
    end

    private

    attr_reader :template

    def content
      return back_in_stock_content if template.back_in_stock?

      case template.layout
      when 'image_left', 'image_right' then side_image_content
      when 'banner' then text_content + coupon + button
      else top_image_content
      end
    end

    def back_in_stock_content
      text_content + [{ 'type' => 'product', 'button_text' => template.button_text }] + coupon
    end

    def top_image_content
      image(template.image) + text_content + coupon + button +
        (template.layout == 'image_top_bottom' ? image(template.image_bottom) : [])
    end

    def side_image_content
      return text_content + coupon + button unless template.image.attached?

      [{
        'type' => 'image_text', 'image_id' => template.image.blob.signed_id,
        'side' => template.layout == 'image_right' ? 'right' : 'left',
        'heading' => template.heading, 'text' => template.body,
        'button_text' => template.button_text, 'link' => template.button_url
      }] + coupon
    end

    def text_content
      [
        { 'type' => 'heading', 'text' => template.heading },
        { 'type' => 'text', 'text' => template.body }
      ]
    end

    def image(attachment)
      return [] unless attachment.attached?

      [{ 'type' => 'image', 'image_id' => attachment.blob.signed_id, 'pad' => 'none' }]
    end

    def coupon
      return [] if template.coupon_code.blank?

      [{ 'type' => 'coupon', 'code' => template.coupon_code }]
    end

    def button
      return [] if template.button_text.blank?

      [{ 'type' => 'button', 'text' => template.button_text, 'link' => template.button_url }]
    end
  end
end
