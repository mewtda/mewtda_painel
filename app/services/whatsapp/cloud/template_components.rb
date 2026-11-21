module Whatsapp
  module Cloud
    # Lê os componentes de um modelo vindo da Meta e devolve os campos do WhatsappTemplate, mais o motivo
    # quando o painel não consegue enviá-lo (o envio só preenche {{1}} do corpo com o primeiro nome).
    class TemplateComponents
      def initialize(data)
        @data = data
        @components = Array(data['components'])
      end

      def to_h
        body = component('BODY') || {}
        header = component('HEADER')
        footer = component('FOOTER')
        url_button = buttons.find { |button| button['type'] == 'URL' }
        {
          body: body['text'].to_s,
          body_example: Array(body.dig('example', 'body_text', 0)).first,
          header_text: (header['text'] if header && header['format'] == 'TEXT'),
          footer: footer&.dig('text'),
          button_text: url_button&.dig('text')&.first(25),
          button_url: url_button&.dig('url'),
          unsupported_reason: unsupported_reason(body, header)
        }
      end

      private

      def component(type) = @components.find { |item| item['type'] == type }

      def buttons = Array(component('BUTTONS')&.dig('buttons'))

      def unsupported_reason(body, header)
        return 'Modelo de autenticação (código de acesso)' if @data['category'] == 'AUTHENTICATION'
        return 'Usa variáveis com nome; o painel só preenche {{1}} com o primeiro nome' if @data['parameter_format'] == 'NAMED'
        if header && header['format'] != 'TEXT'
          kind = { 'IMAGE' => 'imagem', 'VIDEO' => 'vídeo', 'DOCUMENT' => 'documento', 'LOCATION' => 'localização' }
                 .fetch(header['format'], header['format'].to_s.downcase)
          return "Cabeçalho com #{kind}; o painel ainda não envia mídia"
        end
        return 'Cabeçalho com variável; o painel só preenche o nome no corpo' if header && variables(header['text']).any?

        extra = variables(body['text']) - ['1']
        return 'Usa variáveis além de {{1}}; o painel só preenche o primeiro nome' if extra.any?
        return 'Botão com variável; o painel ainda não preenche o link' if buttons.any? { |button| variables(button['url']).any? }

        nil
      end

      def variables(text) = text.to_s.scan(/\{\{\s*(\w+)\s*\}\}/).flatten
    end
  end
end
