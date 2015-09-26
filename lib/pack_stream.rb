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

  class NumberPacker
    def pack object
      marker_and_number, format_string = data_for object

      marker_and_number.pack('C' + format_string.to_s).force_encoding "UTF-8"
    end

    def data_for number
      marker_and_number, format_string = case number
                                           when -9_223_372_036_854_775_808..-2_147_483_649
                                             [[0xCB, number], 'q']
                                           when -2_147_483_648..-32_769
                                             [[0xCA, number], 'l']
                                           when -32_768..-129
                                             [[0xC9, number], 's']
                                           when -128..-17
                                             [[0xC8, number], 'c']
                                           when -16..127
                                             [[number], '']
                                           when 128..32_767
                                             [[0xC9, number], 's']
                                           when 32_768..2_147_483_647
                                             [[0xCA, number], 'l']
                                           when 2_147_483_648..9_223_372_036_854_775_807
                                             [[0xCB, number], 'q']
                                         end

      [marker_and_number, format_string]
    end
  end

  class Packer
    TYPE_TO_PACKER = {
        NilClass => SingleValuePacker.new(0xC0),
        FalseClass => SingleValuePacker.new(0xC2),
        TrueClass => SingleValuePacker.new(0xC3),
        Fixnum => NumberPacker.new,
        Bignum => NumberPacker.new
    }

    def initialize(object)
      @object = object
    end

    def pack
      packer_for(@object).pack @object
    end

  private
    def packer_for object
      TYPE_TO_PACKER[object.class]
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
