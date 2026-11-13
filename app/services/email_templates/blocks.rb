module EmailTemplates
  # Esquema dos blocos do editor de e-mail. Tudo que chega do navegador passa
  # por .sanitize: só tipos e campos conhecidos, valores em listas fechadas,
  # cores hex, links http(s). O HTML final é montado só no servidor.
  module Blocks
    ALIGN = %w[center left right].freeze
    PADDING = %w[md none sm lg].freeze
    HEX_COLOR = /\A#[0-9a-fA-F]{6}\z/
    SAFE_URL = %r{\Ahttps?://\S+\z}
    MAX_BLOCKS = 60
    MAX_TEXT = 5_000
    MAX_GALLERY_ITEMS = 3
    MAX_MENU_ITEMS = 8
    MAX_LABEL = 60

    COMMON = { 'bg' => :color, 'pad' => PADDING }.freeze

    TYPES = {
      'logo' => { 'align' => ALIGN, 'size' => %w[md sm lg] },
      'heading' => { 'text' => :text, 'size' => %w[lg sm md xl], 'align' => ALIGN, 'color' => :color },
      'text' => { 'text' => :text, 'size' => %w[md sm lg], 'align' => ALIGN, 'color' => :color },
      'image' => {
        'image_id' => :image, 'link' => :url, 'alt' => :text, 'width' => %w[100 75 50],
        'align' => ALIGN, 'rounded' => :bool
      },
      'button' => {
        'text' => :text, 'link' => :url, 'align' => ALIGN, 'color' => :color, 'text_color' => :color,
        'style' => %w[filled outline], 'full' => :bool
      },
      'coupon' => { 'code' => :text, 'label' => :text, 'color' => :color },
      'product' => { 'button_text' => :text, 'color' => :color },
      'image_text' => {
        'image_id' => :image, 'side' => %w[left right], 'heading' => :text, 'text' => :text,
        'button_text' => :text, 'link' => :url, 'color' => :color
      },
      'gallery' => { 'items' => :items },
      'divider' => { 'color' => :color, 'thickness' => %w[1 2 4] },
      'spacer' => { 'height' => %w[24 8 16 32 48 64 96] },
      'social' => {
        'instagram' => :url, 'facebook' => :url, 'tiktok' => :url, 'youtube' => :url, 'whatsapp' => :url,
        'linkedin' => :url, 'x' => :url, 'pinterest' => :url, 'site' => :url,
        'shape' => %w[circle square], 'tone' => %w[custom brand], 'color' => :color, 'size' => %w[md sm lg], 'align' => ALIGN
      },
      'menu' => { 'items' => :links, 'size' => %w[md sm lg], 'align' => ALIGN, 'color' => :color, 'uppercase' => :bool }
    }.freeze

    GALLERY_ITEM = { 'image_id' => :image, 'link' => :url, 'caption' => :text }.freeze
    LINK_ITEM = { 'label' => :label, 'link' => :url }.freeze

    FONTS = {
      'arial' => 'Arial, Helvetica, sans-serif',
      'helvetica' => "'Helvetica Neue', Helvetica, Arial, sans-serif",
      'verdana' => 'Verdana, Geneva, sans-serif',
      'trebuchet' => "'Trebuchet MS', Tahoma, sans-serif",
      'georgia' => 'Georgia, Times, serif',
      'times' => "'Times New Roman', Times, serif"
    }.freeze

    DESIGN = {
      'bg' => [:color, '#f4f4f5'],
      'content_bg' => [:color, '#ffffff'],
      'text_color' => [:color, '#111111'],
      'font' => [FONTS.keys, 'arial'],
      'radius' => [%w[12 0 4 24], '12'],
      'preheader' => [:text, '']
    }.freeze

    module_function

    def sanitize(raw)
      list = parse(raw)
      return [] unless list.is_a?(Array)

      list.first(MAX_BLOCKS).filter_map { |block| sanitize_block(block) }
    end

    def sanitize_design(raw)
      data = parse(raw)
      data = {} unless data.is_a?(Hash)

      DESIGN.to_h { |key, (kind, default)| [key, clean(kind, data[key]).presence || default] }
    end

    def sanitize_block(block)
      return unless block.is_a?(Hash)

      type = block['type'].to_s
      fields = TYPES[type]
      return unless fields

      id = block['id'].to_s.gsub(/[^a-zA-Z0-9_-]/, '').first(40).presence || SecureRandom.hex(6)
      clean_fields(COMMON.merge(fields), block).merge('id' => id, 'type' => type)
    end

    def clean_fields(fields, source)
      fields.to_h { |key, kind| [key, clean(kind, source[key])] }
    end

    def clean(kind, value)
      case kind
      when Array then kind.include?(value.to_s) ? value.to_s : kind.first
      when :text then value.to_s.first(MAX_TEXT)
      when :url then url(value)
      when :color then value.to_s.match?(HEX_COLOR) ? value.to_s.downcase : ''
      when :image then value.to_s.first(600)
      when :bool then ActiveModel::Type::Boolean.new.cast(value) ? true : false
      when :items then items(value)
      when :links then links(value)
      when :label then value.to_s.strip.first(MAX_LABEL)
      end
    end

    def url(value)
      value = value.to_s.strip.first(2_000)
      value.match?(SAFE_URL) ? value : ''
    end

    def items(value)
      return [] unless value.is_a?(Array)

      value.first(MAX_GALLERY_ITEMS).filter_map { |item| clean_fields(GALLERY_ITEM, item) if item.is_a?(Hash) }
    end

    def links(value)
      return [] unless value.is_a?(Array)

      value.first(MAX_MENU_ITEMS).filter_map { |item| clean_fields(LINK_ITEM, item) if item.is_a?(Hash) }
    end

    # Aceita JSON (vindo do formulário) ou estruturas Ruby; normaliza as chaves
    # pra string passando sempre por JSON.
    def parse(raw)
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      JSON.parse(raw.is_a?(String) ? raw : raw.to_json)
    rescue JSON::ParserError
      nil
    end

    def image_ids(blocks)
      blocks.flat_map { |block| [block['image_id'], *Array(block['items']).map { |item| item['image_id'] }] }
            .compact_blank
    end
  end
end
