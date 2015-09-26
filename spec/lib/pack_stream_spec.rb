require './lib/pack_stream'

describe PackStream do
  describe PackStream::Unpacker do
    describe '#unpack' do
      def unpacked string
        PackStream::Unpacker.new(StringIO.new(string)).unpack
      end

      context "Null" do
        it "unpacks nil" do
          expect(unpacked "\xC0").to eq(nil)
        end
      end

      context "Booleans" do
        it "unpacks false" do
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

        it "unpacks negative INT_8" do
          expect(unpacked [0xC8, -128].pack("Cc")).to eq(-128)
          expect(unpacked [0xC8, -17].pack("Cc")).to eq(-17)
        end

        it "unpacks negative INT_16" do
          expect(unpacked [0xC9, -32_768].pack("Cs")).to eq(-32_768)
          expect(unpacked [0xC9, -129].pack("Cs")).to eq(-129)
        end

        it "unpacks positive INT_16" do
          expect(unpacked [0xC9, 128].pack("Cs")).to eq(128)
          expect(unpacked [0xC9, 32_767].pack("Cs")).to eq(32_767)
        end

        it "unpacks negative INT_32" do
          expect(unpacked [0xCA, -2_147_483_648].pack("Cl")).to eq(-2_147_483_648)
          expect(unpacked [0xCA, -32_769].pack("Cl")).to eq(-32_769)
        end

        it "unpacks positive INT_32" do
          expect(unpacked [0xCA, 32_768].pack("Cl")).to eq(32_768)
          expect(unpacked [0xCA, 2_147_483_647].pack("Cl")).to eq(2_147_483_647)
        end

        it "unpacks negative INT_64" do
          expect(unpacked [0xCB, -9_223_372_036_854_775_808].pack("Cq")).to eq(-9_223_372_036_854_775_808)
          expect(unpacked [0xCB, -2_147_483_649].pack("Cq")).to eq(-2_147_483_649)
        end

        it "unpacks positive INT_64" do
          expect(unpacked [0xCB, 2_147_483_648].pack("Cq")).to eq(2_147_483_648)
          expect(unpacked [0xCB, 9_223_372_036_854_775_807].pack("Cq")).to eq(9_223_372_036_854_775_807)
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
    describe '#pack' do
      def packed object
        PackStream::Packer.new(object).pack
      end

      context "Null" do
        it "packs nil" do
          expect(packed nil).to eq("\xC0")
        end
      end

      context "Booleans" do
        it "packs false" do
          expect(packed false).to eq("\xC2")
        end

        it "packs true" do
          expect(packed true).to eq("\xC3")
        end
      end
      
      context "Integers" do
        it "packs negative TINY_INT" do
          expect(packed -16).to eq("\xF0")
          expect(packed -1).to eq("\xFF")
        end

        it "packs positive TINY_INT" do
          expect(packed 0).to eq("\x00")
          expect(packed 127).to eq("\x7F")
        end

        it "packs negative INT_8" do
          expect(packed -128).to eq("\xC8\x80")
          expect(packed -17).to eq("\xC8\xEF")
        end

        it "packs negative INT_16" do
          expect(packed -32_768).to eq("\xC9\x00\x80")
          expect(packed -129).to eq("\xC9\x7F\xFF")
        end

        it "packs positive INT_16" do
          expect(packed 128).to eq("\xC9\x80\x00")
          expect(packed 32_767).to eq("\xC9\xFF\x7F")
        end

        it "packs negative INT_32"
        it "packs positive INT_32"
        it "packs negative INT_64"
        it "packs positive INT_64"
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
end
