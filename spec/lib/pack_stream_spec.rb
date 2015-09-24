require './lib/pack_stream'

describe PackStream do
  describe PackStream::Unpacker do
    describe '#unpack_value!' do
      def unpacked string
        PackStream::Unpacker.new(StringIO.new(string)).unpack_value!
      end

      context "Null" do
        it "unpacks nil" do
          expect(unpacked "\xC0").to eq(nil)
        end
      end

      context "Booleans" do
        it "unpacks false" do
          result = unpacked("\xC2")
          expect(unpacked "\xC2").to eq(false)
        end
        it "unpacks true" do
          expect(unpacked "\xC3").to eq(true)
        end
      end

      context "Integers" do
        it "unpacks positive TINY_INT" do
          expect(unpacked "\x7F").to eq(127)
        end

        it "unpacks negative TINY_INT" do
          expect(unpacked "\xF0").to eq(-16)
        end

        it "unpacks all negative TINY_INT values" do
          (-16..-1).each do |number|
            expect(unpacked([0xF0 + number + 0x10].pack("C"))).to eq(number)
          end
        end

        it "unpacks all positive TINY_INT values" do
          (0..127).each do |number|
            expect(unpacked([number].pack("C"))).to eq(number)
          end
        end
      end

      context "Float"
      context "Text"
      context "List"
      context "Map"
      context "Node"
      context "Relationship"
      context "Path"
    end
  end

  describe PackStream::Packer do
    describe '#packed_stream' do
      let(:packer) { PackStream::Packer.new(input) }
      let(:output) { packer.packed_stream }

      # rubocop:disable Metrics/LineLength
      [
        [nil, "\xC0"],
        [false, "\xC2"],
        [true, "\xC3"],

        # Integers
        [-17, '????'],
        [-16, '????'],
        [0, "\x00"],
        [1, "\x01"],
        [42, "\x2A"],
        [127, "\x7F"],
        [128, "\xC9\x00\x80"],
        [32_767, "\xC9\x7F\xFF"],
        [32_768, "\xCA\x00\x00\x80\x00"],
        [2_147_483_647, "\xCA\x7F\xFF\xFF\xFF"],
        [2_147_483_648, "\xCB\x00\x00\x00\x00\x80\x00\x00\x00"],
        [9_223_372_036_854_775_807, "\xCB\x7F\xFF\xFF\xFF\xFF\xFF\xFF\xFF"],

        # Strings
        ['', "\x80"],
        ['Hello', "\x85Hello"],
        ['Hello dolly!!!!', "\x8FHello dolly!!!!"],
        ['Hello dolly!!!!!', "\xD0\x10Hello dolly!!!!!"],

        # Lists
        [[true, false], "\x92\xC3\xC2"],

        [[nil, 42], "\x92\xC0\x2A"],

        [(0..14).to_a, "\x9F\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E"],
        [(0..15).to_a, "\xD4\x10\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F"],

        # Maps
        [{42 => false, 'Hello' => true}, "\xA2\x2A\xC2\x85\x48\x65\x6C\x6C\x6F\xC3"],

        # Structs
        [[true, false].freeze, "\xB2\xC3\xC2"],

        [[nil, 42].freeze, "\xB2\xC0\x2A"],

        [(0..14).to_a.freeze, "\xBF\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E"],
        [(0..15).to_a.freeze, "\xDC\x10\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F"]
        # rubocop:enable Metrics/LineLength
      ].each do |i, o|
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
