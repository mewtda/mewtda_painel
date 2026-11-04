require 'test_helper'

class Whatsapp::MediaTest < ActiveSupport::TestCase
  MP4_HEADER = "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b
  WEBP_HEADER = ("RIFF\x24\x00\x00\x00WEBPVP8 \x18\x00\x00\x00".b + ("\x00" * 24).b).freeze
  WEBM_HEADER = ("\x1A\x45\xDF\xA3\x9F\x42\x82\x84webm\x86\x85V_VP8".b + ("\x00" * 32).b).freeze

  def message_with_kind(kind)
    client = Client.create!(name: 'Loja A', email: "a-#{SecureRandom.hex(4)}@example.com")
    connection = client.whatsapp_connections.create!(name: 'A1')
    contact = connection.contacts.create!(provider_jid: '5511988887777@s.whatsapp.net')
    conversation = connection.conversations.create!(contact: contact)
    conversation.messages.create!(connection: connection, direction: 'incoming', kind: kind, state: 'received',
                                  sent_at: Time.current, media_state: 'pending')
  end

  test 'store! mantém figurinha recebida como sticker' do
    message = message_with_kind('sticker')
    Whatsapp::Media.store!(message, StringIO.new(WEBP_HEADER), filename: 'figurinha.webp')

    assert_equal 'sticker', message.reload.kind
    assert_equal 'ready', message.media_state
  end

  test 'store! mantém vídeo webm recebido como video' do
    message = message_with_kind('video')
    Whatsapp::Media.store!(message, StringIO.new(WEBM_HEADER), filename: 'clip.webm')

    assert_equal 'video', message.reload.kind
    assert_equal 'ready', message.media_state
  end

  test 'store! deduz o tipo quando a mensagem ainda não é de mídia' do
    message = message_with_kind('text')
    Whatsapp::Media.store!(message, StringIO.new(MP4_HEADER), filename: 'clip.mp4')

    assert_equal 'video', message.reload.kind
    assert_equal 'ready', message.media_state
  end

  test 'inspect_upload aceita mp4 como vídeo' do
    type, kind, name = Whatsapp::Media.inspect_upload(StringIO.new(MP4_HEADER), filename: 'clip.mp4')

    assert_equal 'video/mp4', type
    assert_equal 'video', kind
    assert_equal 'clip.mp4', name
  end

  test 'inspect_upload rejeita arquivo de 17 MB' do
    io = StringIO.new(MP4_HEADER + ('0' * 17.megabytes))

    assert_raises(Whatsapp::Media::Invalid) { Whatsapp::Media.inspect_upload(io, filename: 'grande.mp4') }
  end

  test 'inspect_upload rejeita executável' do
    io = StringIO.new('MZ'.b + ("\x00" * 64))
    io.define_singleton_method(:size) { 66 }

    error = assert_raises(Whatsapp::Media::Invalid) { Whatsapp::Media.inspect_upload(io, filename: 'a.exe') }
    assert_includes error.message, 'Formato não permitido'
  end

  test 'inspect_upload aceita csv como documento' do
    _type, kind, = Whatsapp::Media.inspect_upload(StringIO.new("a,b\n1,2\n"), filename: 'dados.csv')
    assert_equal 'document', kind
  end

  test 'store! em produção exige WHATSAPP_STORAGE_SERVICE' do
    message = message_with_kind('image')
    original = ENV.delete('WHATSAPP_STORAGE_SERVICE')
    Rails.stub(:env, ActiveSupport::StringInquirer.new('production')) do
      error = assert_raises(Whatsapp::Media::Invalid) do
        Whatsapp::Media.store!(message, StringIO.new(WEBP_HEADER), filename: 'a.webp')
      end
      assert_match(/WHATSAPP_STORAGE_SERVICE/, error.message)
    end
  ensure
    ENV['WHATSAPP_STORAGE_SERVICE'] = original if original
  end
end
