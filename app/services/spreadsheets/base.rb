require 'rubyXL/convenience_methods'

module Spreadsheets
  class Base
    CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze

    def content_type = CONTENT_TYPE

    def to_xlsx
      workbook = RubyXL::Workbook.new
      sheet = workbook[0]
      sheet.sheet_name = sheet_name
      write_row(sheet, 0, headers)
      rows.each.with_index(1) { |values, index| write_row(sheet, index, values) }
      workbook.stream.string
    end

    private

    def stamp = Time.current.strftime('%Y%m%d_%H%M')

    def write_row(sheet, index, values)
      values.each_with_index { |value, column| sheet.add_cell(index, column, value) }
    end
  end
end
