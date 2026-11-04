require 'stringio'
require 'base64'
module Whatsapp
  # Uses private storage directly: no public ActiveStorage blob/signed-ID routes.
  class Media < ApplicationRecord
    self.table_name = 'whatsapp_media'
    belongs_to :message
    MAX_BYTES = 16.megabytes
    MEDIA_KINDS = %w[image video audio document sticker].freeze
    DOCUMENT_TYPES = %w[
      application/pdf text/plain text/csv application/msword application/vnd.ms-excel application/zip
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.openxmlformats-officedocument.presentationml.presentation
    ].freeze
    TYPES = ({
      'image/jpeg' => 'image', 'image/png' => 'image', 'image/webp' => 'image', 'image/gif' => 'image',
      'audio/mpeg' => 'audio', 'audio/ogg' => 'audio', 'audio/x-wav' => 'audio', 'audio/wav' => 'audio',
      'audio/mp4' => 'audio', 'audio/webm' => 'audio', 'video/webm' => 'audio',
      'video/mp4' => 'video', 'video/3gpp' => 'video', 'video/quicktime' => 'video'
    }.merge(DOCUMENT_TYPES.index_with { 'document' })).freeze
    FORMATS_MESSAGE = 'Formato não permitido. Use JPG, PNG, WEBP, GIF, PDF, TXT, CSV, DOC, DOCX, XLS, XLSX, ZIP, ' \
                      'áudio ou vídeo (MP4, 3GP, MOV).'.freeze
    class Invalid < StandardError; end
    class NotConfigured < StandardError; end

    def self.inspect_upload(io, filename:)
      raise Invalid, 'O arquivo deve ter até 16 MB.' if io.size > MAX_BYTES || io.size.zero?

      io.rewind
      type = Marcel::MimeType.for(io)
      io.rewind
      if type == 'application/octet-stream' && %w[.txt .csv].include?(File.extname(filename.to_s).downcase)
        text = io.read.force_encoding(Encoding::UTF_8)
        if text.valid_encoding? && !text.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f]/) && !text.lstrip.start_with?('<')
          type = File.extname(filename.to_s).downcase == '.csv' ? 'text/csv' : 'text/plain'
        end
        io.rewind
      end
      raise Invalid, FORMATS_MESSAGE unless TYPES.key?(type)

      [type, TYPES.fetch(type), File.basename(filename.to_s).gsub(/[\x00-\x1f]/, '').truncate(150).presence || 'arquivo']
    end

    def self.store!(message, io, filename:)
      type, kind, safe_name = inspect_upload(io, filename: filename)
      service_name = ENV['WHATSAPP_STORAGE_SERVICE'].presence
      if service_name.nil?
        raise NotConfigured, 'WHATSAPP_STORAGE_SERVICE não configurado.' if Rails.env.production?

        service_name = Rails.application.config.active_storage.service.to_s
      end
      service = ActiveStorage::Blob.services.fetch(service_name)
      key = "whatsapp/#{SecureRandom.hex(32)}"
      record = new(message: message, storage_key: key, service_name: service_name, filename: safe_name,
                   content_type: type, byte_size: io.size)
      begin
        service.upload(key, io, content_type: type)
        record.save!
        # Ingest já define o tipo pela mensagem do WhatsApp (figurinha, vídeo webm); só uploads novos o deduzem.
        message.update!(kind: MEDIA_KINDS.include?(message.kind) ? message.kind : kind, media_state: 'ready')
      rescue StandardError
        service.delete(key)
        raise
      end
      record
    end

    def download = ActiveStorage::Blob.services.fetch(service_name).download(storage_key)
  end
end
