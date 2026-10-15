# Marshal.dump для UTF-8 String — единственный срез Marshal, нужный
# вне railties (полезная нагрузка SignedGlobalID / globalid-гема;
# см. railties.cr/credentials.cr MarshalStringCodec — там он для
# EncryptedFile).
#
# Wire (Ruby Marshal 4.8, строка с encoding-ivar):
#   04 08 49 22 <len+5> <bytes...> 06 3a 06 45 54
# где длина 1..117 кодируется байтом len+5 (Marshal Fixnum для 6..122;
# строки короче 6 не поддерживаем — gid-URI всегда длиннее).

module ActiveSupport
  module MarshalString
    def self.dump(value : String) : String
      bytes = value.to_slice
      size = bytes.size
      unless 1 <= size <= 117
        raise ArgumentError.new("MarshalString: #{size} bytes out of supported range 1..117")
      end

      String.build do |io|
        io.write Bytes[0x04, 0x08, 0x49, 0x22]
        io.write_byte((size + 5).to_u8)
        io.write bytes
        io.write Bytes[0x06, 0x3a, 0x06, 0x45, 0x54] # ivars: {:E => T}
      end
    end

    # Строгий разбор кадра, порождённого #dump; иначе nil.
    def self.load(raw : String) : String?
      bytes = raw.to_slice
      return nil unless bytes.size > 10
      return nil unless bytes[0, 4] == Bytes[0x04, 0x08, 0x49, 0x22]

      len = bytes[4].to_i - 5
      return nil unless 1 <= len <= 117
      return nil unless bytes.size == 5 + len + 5
      return nil unless bytes[5 + len, 5] == Bytes[0x06, 0x3a, 0x06, 0x45, 0x54]

      String.new(bytes[5, len])
    end
  end
end
