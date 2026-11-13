module EmailTemplates
  # Monta o e-mail final (assunto, HTML e texto) a partir dos blocos de um
  # EmailTemplate. Variáveis como {nome}, {loja} e {produto} são substituídas
  # em todos os textos.
  class Message
    VARIABLE = /\{(\w+)\}/
    DEFAULT_ACCENT_COLOR = '#7c3aed'.freeze
    HEX_COLOR = /\A#[0-9a-fA-F]{6}\z/
    SAFE_URL = %r{\Ahttps?://}

    PADDING = { 'none' => '0', 'sm' => '12px 24px', 'md' => '20px 32px', 'lg' => '36px 40px' }.freeze
    HEADING_SIZES = { 'sm' => 18, 'md' => 22, 'lg' => 26, 'xl' => 34 }.freeze
    TEXT_SIZES = { 'sm' => 13, 'md' => 15, 'lg' => 17 }.freeze
    LOGO_HEIGHTS = { 'sm' => 32, 'md' => 48, 'lg' => 72 }.freeze
    BUTTON_RADIUS = { '0' => 0, '4' => 4, '12' => 8, '24' => 999 }.freeze
    SOCIAL_LABELS = {
      'instagram' => 'Instagram', 'facebook' => 'Facebook', 'tiktok' => 'TikTok',
      'youtube' => 'YouTube', 'whatsapp' => 'WhatsApp', 'site' => 'Site'
    }.freeze

    attr_reader :logo_url, :unsubscribe_url, :product

    # product: { title:, variant:, image:, url: } — usado pelo bloco "Produto".
    # default_url: destino de botões sem link próprio.
    # asset_url: lambda que transforma um ActiveStorage::Blob em URL pública.
    # preview: marca os blocos pra seleção por clique no editor.
    def initialize(template, variables: {}, product: nil, default_url: nil, logo_url: nil, # rubocop:disable Metrics/ParameterLists
                   unsubscribe_url: nil, asset_url: nil, preview: false)
      @template = template
      @variables = variables.stringify_keys
      @product = product
      @default_url = default_url
      @logo_url = logo_url
      @unsubscribe_url = unsubscribe_url
      @asset_url = asset_url || method(:public_blob_url)
      @preview = preview
      @images = {}
    end

    def preview?
      @preview
    end

    def subject
      interpolate(@template.subject)
    end

    def preheader
      interpolate(design['preheader'])
    end

    def blocks
      @blocks ||= @template.content_blocks
    end

    def design
      @design ||= @template.design
    end

    def store_name
      @variables['loja']
    end

    def accent_color
      @template.accent_color.to_s.match?(HEX_COLOR) ? @template.accent_color : DEFAULT_ACCENT_COLOR
    end

    def font_family
      Blocks::FONTS.fetch(design['font'])
    end

    def radius
      design['radius'].to_i
    end

    def button_radius
      BUTTON_RADIUS.fetch(design['radius'], 8)
    end

    def color(value, fallback = accent_color)
      value.to_s.match?(HEX_COLOR) ? value : fallback
    end

    def text_color(block)
      color(block['color'], design['text_color'])
    end

    def padding(block)
      PADDING.fetch(block['pad'], PADDING['md'])
    end

    def heading_size(block) = HEADING_SIZES.fetch(block['size'], 26)
    def text_size(block) = TEXT_SIZES.fetch(block['size'], 15)
    def logo_height(block) = LOGO_HEIGHTS.fetch(block['size'], 48)

    def link(url)
      [url, @default_url].find { |candidate| candidate.to_s.match?(SAFE_URL) }
    end

    def image_url(image_id)
      return if image_id.blank?

      @images.fetch(image_id) do
        blob = ActiveStorage::Blob.find_signed(image_id)
        @images[image_id] = (@asset_url.call(blob) if blob)
      end
    end

    def interpolate(text)
      text.to_s.gsub(VARIABLE) { @variables.fetch(Regexp.last_match(1), Regexp.last_match(0)).to_s }
    end

    # Texto com formatação leve: **negrito**, *itálico*, [texto](https://link),
    # quebras de linha e parágrafos. Tudo é escapado antes de formatar.
    def rich_text(text, link_color: accent_color)
      escaped = ERB::Util.html_escape(interpolate(text)).to_str
      formatted = escaped
                  .gsub(%r{\[([^\]\n]+)\]\((https?://[^\s)]+)\)}) do
                    %(<a href="#{Regexp.last_match(2)}" target="_blank" style="color: #{link_color};">#{Regexp.last_match(1)}</a>)
                  end
                  .gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
                  .gsub(/(?<![*\w])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![*\w])/, '<em>\1</em>')
      paragraphs = formatted.split(/\n{2,}/).map { |paragraph| paragraph.strip.gsub("\n", '<br>') }.compact_blank
      paragraphs.each_with_index.map do |paragraph, index|
        margin = index == paragraphs.size - 1 ? '0' : '0 0 12px'
        %(<p style="margin: #{margin};">#{paragraph}</p>)
      end.join.html_safe # rubocop:disable Rails/OutputSafety
    end

    def html
      ApplicationController.render(partial: 'email_templates/email', locals: { message: self })
    end

    def text
      parts = [store_name, *blocks.flat_map { |block| text_parts(block) }, unsubscribe_line]
      parts.compact_blank.join("\n\n")
    end

    private

    def text_parts(block)
      case block['type']
      when 'heading', 'text' then [plain(block['text'])]
      when 'button' then [link_line(block['text'], link(block['link']))]
      when 'coupon' then [[interpolate(block['label']), block['code']].compact_blank.join(': ')]
      when 'image_text' then [plain(block['heading']), plain(block['text']), link_line(block['button_text'], link(block['link']))]
      when 'product' then product_text(block)
      else []
      end
    end

    def product_text(block)
      return [] unless product

      summary = [product[:title], ("Variação: #{product[:variant]}" if product[:variant].present?)].compact.join("\n")
      [summary, link_line(block['button_text'], link(product[:url]))]
    end

    def plain(text)
      interpolate(text).gsub(%r{\[([^\]\n]+)\]\((https?://[^\s)]+)\)}, '\1 (\2)').gsub(/\*\*?/, '')
    end

    def link_line(label, url)
      return if url.blank?

      [interpolate(label).presence, url].compact.join(': ')
    end

    def unsubscribe_line
      "Não quero mais receber estes e-mails: #{unsubscribe_url}" if unsubscribe_url
    end

    def public_blob_url(blob)
      Rails.application.routes.url_helpers.rails_blob_url(blob, host: BackInStockSetting::WIDGET_HOST)
    end
  end
end
