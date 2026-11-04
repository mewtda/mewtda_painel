require 'test_helper'

class Whatsapp::MediaTest < ActiveSupport::TestCase
  MP4_HEADER = "\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom".b

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
end
