require 'rubyXL/convenience_methods'
require 'csv'

# Importa clientes para uma lista estática a partir de uma planilha (.xlsx ou .csv)
# com e-mails. Lê todas as células da planilha, extrai o que parece e-mail e
# adiciona à lista os clientes da loja que tiverem esse e-mail.
module Segments
  class EmailImport
    EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
    Result = Struct.new(:found, :added, :not_found, keyword_init: true)

    class InvalidFile < StandardError; end

    def self.template_xlsx
      workbook = RubyXL::Workbook.new
      sheet = workbook[0]
      sheet.sheet_name = 'Clientes'
      sheet.add_cell(0, 0, 'email')
      sheet.add_cell(1, 0, 'cliente@exemplo.com')
      sheet.change_column_width(0, 40)
      workbook.stream.string
    end

    def initialize(segment, file)
      @segment = segment
      @file = file
    end

    def call
      emails = extract_emails
      profiles = @segment.client.customer_profiles.where('LOWER(customer_profiles.email) IN (?)', emails.presence || [''])
      matched = profiles.pluck(:customer_id, Arel.sql('LOWER(customer_profiles.email)'))
      added = insert(matched.map(&:first).uniq)
      @segment.recount!
      Result.new(found: emails.size, added:, not_found: emails - matched.map(&:last))
    end

    private

    def extract_emails
      cells.filter_map { |value| value.to_s.strip.downcase.delete_prefix('mailto:').presence }
           .select { |value| value.match?(EMAIL) }.uniq
    end

    def cells
      case File.extname(@file.original_filename.to_s).downcase
      when '.xlsx' then xlsx_cells
      when '.csv', '.txt' then csv_cells
      else raise InvalidFile, 'Envie a planilha em .xlsx ou .csv.'
      end
    rescue InvalidFile
      raise
    rescue StandardError
      raise InvalidFile, 'Não foi possível ler a planilha. Use o modelo (.xlsx ou .csv).'
    end

    def xlsx_cells
      values = []
      RubyXL::Parser.parse_buffer(File.binread(@file.path)).worksheets.each do |sheet|
        sheet.each { |row| row&.cells.to_a.each { |cell| values << cell&.value } }
      end
      values
    end

    def csv_cells
      text = File.read(@file.path, encoding: 'bom|utf-8')
      text = text.encode('UTF-8', 'ISO-8859-1') unless text.valid_encoding?
      separator = text.lines.first.to_s.count(';') > text.lines.first.to_s.count(',') ? ';' : ','
      CSV.parse(text, col_sep: separator).flatten
    end

    def insert(customer_ids)
      return 0 if customer_ids.empty?

      existing = @segment.segment_memberships.where(customer_id: customer_ids).pluck(:customer_id)
      now = Time.current
      rows = (customer_ids - existing).map { |id| { segment_id: @segment.id, customer_id: id, created_at: now, updated_at: now } }
      SegmentMembership.insert_all(rows, unique_by: %i[segment_id customer_id]) if rows.any?
      rows.size
    end
  end
end
