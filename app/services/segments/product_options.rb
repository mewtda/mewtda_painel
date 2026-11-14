module Segments
  class ProductOptions
    SIZE_TOKEN = /\A(?:[PMG]{1,3}|[XE]{0,2}[GP]|U|\d{2})\z/
    SIZE_ORDER = %w[PP P M G GG XG XGG].freeze

    def initialize(client)
      @client = client
    end

    def categories
      products.where.not(tags: [nil, '']).pluck(:tags).flat_map { |tags| tags.split(',').map(&:strip) }
              .compact_blank.tally.sort_by { |name, count| [-count, name] }.map { |name, _| { key: name, label: name } }
    end

    def sizes
      tokens = products.pluck(:option1, :option2, :option3).flatten.compact.filter_map { |option| token(option) }.uniq
      tokens.sort_by { |size| [SIZE_ORDER.index(size) || SIZE_ORDER.size, size] }.map { |size| { key: size, label: size } }
    end

    private

    attr_reader :client

    def products = Product.where(client_id: client.id)

    def token(option)
      value = option.split('/').first.to_s.strip.upcase
      value if value.match?(SIZE_TOKEN)
    end
  end
end
