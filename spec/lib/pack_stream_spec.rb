require './lib/pack_stream'

describe PackStream do
  describe PackStream::Packer do
    describe '#unpack_value!' do
      let(:unpacker) { PackStream::Unpacker.new(input) }
      let(:output) { unpacker.unpack_value! }

      # rubocop:disable Metrics/LineLength
      {
        "\xC0" => nil,
        "\xC2" => false,
        "\xC3" => true,

        # Integers
        "\x2A" => 42,
        "\xC8\x2A" => 42,
        "\xC9\x00\x2A" => 42,
        "\xCA\x00\x00\x00\x2A" => 42,
        "\xCB\x00\x00\x00\x00\x00\x00\x00\x2A" => 42,
        "\xCB\x01\x02\x03\x04" => 16_909_060,

        # Tiny Text
        "\x80" => '',
        "\x85\x48\x65\x6C\x6C\x6F" => 'Hello',

        # Text
        "\xD0\x11\x4E\x65\x6F\x34\x6A\x20\x69\x73\x20\x61\x77\x65\x73\x6F\x6D\x65\x21" => 'Neo4j is awesome!',

        # Tiny List
        "\x92\xC3\xC2" => [true, false],

        # List
        "\xD4\x02\xC0\xCA\x00\x00\x00\x2A" => [nil, 42],

        # Tiny Map
        "\xA2\x2A\xC2\x85\x48\x65\x6C\x6C\x6F\xC3" => {42 => false, 'Hello' => true},

        # Map
        "\xD8\x02\x2A\xC2\x85\x48\x65\x6C\x6C\x6F\xC3" => {42 => false, 'Hello' => true},

        # Tiny Struct
        "\xB2\xC3\xC2" => [true, false],

        # Struct
        "\xDC\x02\xC0\xCA\x00\x00\x00\x2A" => [nil, 42]

        # rubocop:enable Metrics/LineLength
      }.each do |i, o|
        context "stream of: #{i.inspect}" do
          let(:input) { i }
          it "should output #{o.inspect}" do
            expect(output).to eq(o)
          end
        end
      end
    end
  end

  describe PackStream::Unpacker do
    describe '#packed_stream' do
      let(:packer) { PackStream::Packer.new(input) }
      let(:output) { packer.packed_stream }

      # rubocop:disable Metrics/LineLength
      {
        nil => "\xC0",
        false => "\xC2",
        true => "\xC3",

        # Integers
        -17  => '????',
        -16  => '????',
        0    => "\x00",
        1    => "\x01",
        42   => "\x2A",
        127  => "\x7F",
        128  => "\xC9\x00\x80",
        32_767 => "\xC9\x7F\xFF",
        32_768 => "\xCA\x00\x00\x80\x00",
        2_147_483_647 => "\xCA\x7F\xFF\xFF\xFF",
        2_147_483_648 => "\xCB\x00\x00\x00\x00\x80\x00\x00\x00",
        9_223_372_036_854_775_807 => "\xCB\x7F\xFF\xFF\xFF\xFF\xFF\xFF\xFF",

        # Strings
        '' => "\x80",
        'Hello' => "\x85Hello",
        'Hello dolly!!!!' => "\x8FHello dolly!!!!",
        'Hello dolly!!!!!' => "\xD0\x10Hello dolly!!!!!",

        # Lists
        [true, false] => "\x92\xC3\xC2",

        [nil, 42] => "\x92\xC0\x2A",

        (0..14).to_a => "\x9F\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E",
        (0..15).to_a => "\xD4\x10\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F",

        # Maps
        {42 => false, 'Hello' => true} => "\xA2\x2A\xC2\x85\x48\x65\x6C\x6C\x6F\xC3",

        # Structs
        [true, false].freeze => "\xB2\xC3\xC2",

        [nil, 42].freeze => "\xB2\xC0\x2A",

        (0..14).to_a.freeze => "\xBF\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E",
        (0..15).to_a.freeze => "\xDC\x10\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F"
        # rubocop:enable Metrics/LineLength
      }.each do |i, o|
        context "object: #{i.inspect}" do
          let(:input) { i }
          it "should output #{o.inspect}" do
            expect(output).to eq(o)
          end
        end
      end
    end
  end
end
