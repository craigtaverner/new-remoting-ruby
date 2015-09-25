require 'stringio'

module PackStream
  class SingleValuePacker
    def initialize default_value
      @default_value = default_value
    end

    def pack object
      [@default_value].pack('c*').force_encoding "UTF-8"
    end
  end

  class Packer
    TYPE_PACKERS = {
        NilClass => SingleValuePacker.new(0xC0),
        FalseClass => SingleValuePacker.new(0xC2),
        TrueClass => SingleValuePacker.new(0xC3)
    }

    def initialize(object)
      @object = object
    end

    def pack
      packer_for_type(@object.class).pack @object
    end

  private
    def packer_for_type kind
      TYPE_PACKERS[kind]
    end
  end

  class SingleValueUnpacker
    def initialize default_value
      @default_value = default_value
    end

    def unpack marker, stream
      @default_value
    end
  end

  class PositiveTinyIntUnpacker
    def unpack marker, stream
      marker.to_i
    end
  end

  class NegativeTinyIntUnpacker
    def unpack marker, stream
      marker.to_i - 0x100
    end
  end

  class IntUnpacker
    def initialize bits
      @bits = bits
    end

    def unpack marker, stream
      stream.read.unpack(pack_format_for @bits).first.to_i
    end

  private
    def pack_format_for bits
      bits_to_pack_format = { 8 => "c",
                             16 => "s",
                             32 => "l",
                             64 => "q", }

      bits_to_pack_format[bits]
    end
  end

  class Unpacker
    MARKER_BYTES = Hash[(0x00..0x7F).map { |byte| [byte, PositiveTinyIntUnpacker.new] } ]
    MARKER_BYTES.merge!(0xC0 => SingleValueUnpacker.new(nil),
                        0xC2 => SingleValueUnpacker.new(false),
                        0xC3 => SingleValueUnpacker.new(true))
    MARKER_BYTES.merge!(0xC8 => IntUnpacker.new(8),
                        0xC9 => IntUnpacker.new(16),
                        0xCA => IntUnpacker.new(32),
                        0xCB => IntUnpacker.new(64))
    MARKER_BYTES.merge!(Hash[(0xF0..0xFF).map { |byte| [byte, NegativeTinyIntUnpacker.new] } ])

    def initialize stream
      @stream = stream
    end

    def unpack
      marker = @stream.read(1).bytes.first
      kind = MARKER_BYTES[marker]
      kind.unpack marker, @stream
    end
  end
end
