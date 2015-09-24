require 'stringio'

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

class TinyTextUnpacker
  def unpack marker, stream
    size = (marker & 0x0F)
    stream.unpack("LL#{size}")[1..size].map { |c| c.chr }.join
  end
end

class PackStreamUnpacker
  MARKER_BYTES = Hash[(0x00..0x7F).map { |byte| [byte, PositiveTinyIntUnpacker.new] } ]
  MARKER_BYTES.merge!(0xC0 => SingleValueUnpacker.new(nil),
                      0xC2 => SingleValueUnpacker.new(false),
                      0xC3 => SingleValueUnpacker.new(true))
  MARKER_BYTES.merge!(Hash[(0xF0..0xFF).map { |byte| [byte, NegativeTinyIntUnpacker.new] } ])
  MARKER_BYTES.merge!(Hash[(0xB0..0xBF).map { |byte| [byte, TinyTextUnpacker.new] } ])

  def unpack packed_stream
    marker = packed_stream.read(1).bytes.first
    kind = MARKER_BYTES[marker]
    kind.unpack marker, packed_stream
  end
end

module PackStream
  MARKER_TYPES = {
      C0: nil,
      C1: [:float, 64],
      C2: false,
      C3: true,
      C8: [:int, 8],
      C9: [:int, 16],
      CA: [:int, 32],
      CB: [:int, 64],
      CC: [:bytes, 8],
      CD: [:bytes, 16],
      CE: [:bytes, 32],
      D0: [:text, 8],
      D1: [:text, 16],
      D2: [:text, 32],
      D4: [:list, 8],
      D5: [:list, 16],
      D6: [:list, 32],
      D8: [:map, 8],
      D9: [:map, 16],
      DA: [:map, 32],
      DC: [:struct, 8],
      DD: [:struct, 16],
      DE: [:struct, 32]
  }

  # For efficiency.  Translates directly from bytes to types
  MARKER_TYPES.keys.each do |key|
    ord = eval("0x#{key}") # rubocop:disable Lint/Eval
    MARKER_TYPES[ord] = MARKER_TYPES.delete(key)
  end
  #
  # Translates directly from types to bytes
  MARKER_BYTES = MARKER_TYPES.invert
  MARKER_BYTES.keys.each do |key|
    MARKER_BYTES.delete(key) if key.is_a?(Array)
  end

  class Packer
    def initialize(object)
      @object = object
    end

    def packed_stream
      if byte = MARKER_BYTES[@object]
        pack_array_as_string([byte])
      else
        case @object
        when Integer, String, Array, Hash
          send(@object.class.name.downcase + '_stream')
        end
      end
    end

    # rubocop:disable Metrics/MethodLength
    def integer_stream
      case @object
      when -0xFF...-0x0F
        "\xC8" + pack_integer_object_as_string
      when -0x0F...0x80
        pack_integer_object_as_string
      when 0x80...0x8000
        "\xC9" + pack_integer_object_as_string(2)
      when 0x8000...0x80000000
        "\xCA" + pack_integer_object_as_string(4)
      when 0x80000000..0x7FFFFFFFFFFFFFFF
        "\xCB" + pack_integer_object_as_string(8)
      end
    end
    # rubocop:enable Metrics/MethodLength

    alias_method :fixnum_stream, :integer_stream
    alias_method :bignum_stream, :integer_stream

    def string_stream
      marker_string(header_bytes(0x80, 0xD0, @object.bytesize)) +
        @object.encode('UTF-8')
    end

    def array_stream
      header = if @object.frozen?
                 header_bytes(0xB0, 0xDC, @object.size)
               else
                 header_bytes(0x90, 0xD4, @object.size)
               end

      marker_string(header) + @object.map do |e|
        Packer.new(e).packed_stream
      end.join
    end

    def hash_stream
      marker_string(header_bytes(0xA0, 0xD8, @object.size)) +
        @object.map do |key, value|
          Packer.new(key).packed_stream +
            Packer.new(value).packed_stream
        end.join
    end

    def self.pack_arguments(*objects)
      objects.map {|o| new(o).packed_stream }.join
    end

    private

    def header_bytes(tiny_base, regular_base, size)
      case size
      when 0...0x10
        [tiny_base + size]
      when 0x10...0xFF
        [regular_base, size]
      when 0xFF...0xFFFF
        [regular_base + 1, size]
      when 0xFFFF...0xFFFFFFFF
        [regular_base + 2, size]
      end
    end

    def marker_string(bytes)
      bytes.pack('c*').force_encoding('UTF-8')
    end

    def pack_integer_object_as_string(size = 1)
      # Array of hex bytes
      a = @object.to_s(16).scan(/..?/).map { |s| s.to_i(16) }

      # left pad with zeros
      a.unshift(0) while a.size < size

      pack_array_as_string(a)
    end

    def pack_array_as_string(a)
      a.pack('c*').force_encoding('UTF-8')
    end
  end

  # Object which holds a stream of PackStream data
  # and can unpack it
  class Unpacker
    def initialize stream
      @stream = stream
    end

    def unpack_value!
      PackStreamUnpacker.new.unpack @stream
    end
  end
end
