# ActiveSupport::MessageEncryptor — порт AS 8.1.4
# (lib/active_support/message_encryptor.rb + messages/{codec,metadata}.rb)
# для AEAD aes-256-gcm — дефолта Rails 8.1-приложений.
#
# Wire-формат 1:1 с гемом:
#   b64(ciphertext) + "--" + b64(iv) + "--" + b64(auth_tag[16])
# (AEAD не подписывается отдельным MessageVerifier — тег и есть подпись).
# Метаданные purpose/exp — конверт Rails 8.1:
#   {"_rails":{"data":<json>,"exp":<iso8601(3)>,"pur":<purpose>}}
# Чтение также понимает legacy-конверт AS 7.0/standalone
# ({"_rails":{"message":<strict-b64(json)>,...}}).
# NullSerializer (credentials.yml.enc): данные шифруются как есть, без
# JSON-обёртки. Опция `force_legacy_metadata_serializer: true` (имя — как
# в гемe) пишет legacy-конверт {"_rails":{"message":strict_b64(json),
# "exp":...,"pur":...}} — wire-формат encrypted cookies actionpack 8.1
# (см. message_verifier.cr; оракул action_pack.cr/oracle/cookies_*).
#
# Отклонение от гема: только AEAD (aes-256-gcm, aes-128-gcm — второй
# это wire credentials.yml.enc: EncryptedFile::CIPHER гема); не-AEAD шифры
# (aes-256-cbc с отдельной подписью) не поддержаны — в CRails они
# не нужны. Криптография — EVP через LibCrypto: у кристалловского
# OpenSSL::Cipher нет auth_tag/auth_data, поэтому ctrl-биндинг
# (EVP_CIPHER_CTX_ctrl) довязан здесь.
#
# Оракулы: oracle/crypto_cases.rb → oracle/crypto_expected.yml
# (kg/me/mv), реверс-направление — oracle/verify_crypto.rb.

require "base64"
require "json"
require "openssl/lib_crypto"

lib LibCrypto
  CTRL_GCM_SET_IVLEN = 0x9
  CTRL_GCM_GET_TAG   = 0x10
  CTRL_GCM_SET_TAG   = 0x11

  fun evp_cipherctx_ctrl = EVP_CIPHER_CTX_ctrl(ctx : EVP_CIPHER_CTX, type : Int32, arg : Int32, ptr : Void*) : Int32
end

module ActiveSupport
  class MessageEncryptor
    class InvalidMessage < Exception
    end

    AUTH_TAG_LENGTH = 16
    SEPARATOR       = "--"

    alias MetadataScalar = String | Int32 | Int64 | Bool | Nil
    alias MetadataPayload = String | Int32 | Int64 | Bool | Nil |
                            Array(String | Symbol) |
                            Hash(String, MetadataScalar)

    # iv aes-256-gcm = 12 байт, ключ = 32 байта.
    def self.key_len(cipher : String = "aes-256-gcm") : Int32
      evp = LibCrypto.evp_get_cipherbyname(cipher)
      raise ArgumentError.new("unknown cipher #{cipher}") unless evp
      LibCrypto.evp_cipher_key_length(evp)
    end

    def self.iv_len(cipher : String = "aes-256-gcm") : Int32
      evp = LibCrypto.evp_get_cipherbyname(cipher)
      raise ArgumentError.new("unknown cipher #{cipher}") unless evp
      LibCrypto.evp_cipher_iv_length(evp)
    end

    @key : Bytes
    @cipher : String
    @url_safe : Bool
    @serializer : Symbol

    def initialize(@secret : String | Bytes,
                   cipher : String = "aes-256-gcm",
                   url_safe : Bool = false,
                   serializer : Symbol = :json,
                   force_legacy_metadata_serializer : Bool = false)
      @cipher = cipher
      @url_safe = url_safe
      @serializer = serializer
      @force_legacy_metadata = force_legacy_metadata_serializer
      raise ArgumentError.new("only AEAD ciphers are supported, got #{@cipher}") \
        unless {"aes-256-gcm", "aes-128-gcm"}.includes?(@cipher)
      @key = case secret = @secret
             in String then secret.to_slice.clone
             in Bytes   then secret
             end
      raise ArgumentError.new("secret must be at least #{self.class.key_len(@cipher)} bytes") \
        if @key.size < self.class.key_len(@cipher)
    end

    # Шифрует значение. С purpose/exp — конверт {"_rails":{...}}
    # (data-конверт Rails 8.1). NullSerializer: значение — строка как есть.
    def encrypt_and_sign(value : MetadataPayload, purpose : String? = nil,
                         expires_in : Time::Span? = nil,
                         expires_at : Time? = nil) : String
      if @serializer == :null
        plaintext = value.to_s
      elsif purpose || expires_in || expires_at
        expiry = expiry_string(expires_in, expires_at)
        plaintext =
          if @force_legacy_metadata
            String.build do |io|
              io << "{\"_rails\":{\"message\":"
              Base64.strict_encode(String.build { |j| json_dump(value, j) }).to_json(io)
              io << ",\"exp\":" << (expiry ? expiry.to_json : "null")
              io << ",\"pur\":" << (purpose ? purpose.to_json : "null")
              io << "}}"
            end
          else
            String.build do |io|
              io << "{\"_rails\":{\"data\":"
              json_dump(value, io)
              io << ",\"exp\":" << expiry.to_json if expiry
              io << ",\"pur\":" << purpose.to_json if purpose
              io << "}}"
            end
          end
      else
        plaintext = String.build { |io| json_dump(value, io) }
      end
      iv = Random::Secure.random_bytes(self.class.iv_len(@cipher))
      data = plaintext.to_slice
      ciphertext, tag = AEAD.encrypt(@cipher, @key, iv, data)
      [ciphertext, iv, tag].map { |part| encode(part) }.join(SEPARATOR)
    end

    # Расшифровывает и проверяет тег. Ошибки формата (base64, разделители,
    # длина тега, провал аутентификации) — InvalidMessage, как в геме;
    # несоответствие purpose/истёкший срок — nil.
    def decrypt_and_verify(message : String,
                           purpose : String? = nil) : JSON::Any | String | Nil
      ciphertext, iv, tag = extract_parts(message)
      plaintext = AEAD.decrypt(@cipher, @key, iv, tag, ciphertext)
      raise InvalidMessage.new("authentication failed") unless plaintext
      serialized = String.new(plaintext)

      if @serializer == :null
        serialized
      else
        parsed = JSON.parse(serialized)
        if envelope = parsed.as_h?.try(&.["_rails"]?).try(&.as_h?)
          extract_envelope(envelope, purpose)
        else
          return nil if purpose # голое сообщение с ожидаемым purpose — nil
          parsed
        end
      end
    rescue ex : ArgumentError | Base64::Error | JSON::ParseException
      raise InvalidMessage.new(ex.message)
    end

    # --- внутреннее -----------------------------------------------------

    private def extract_envelope(rails : Hash(String, JSON::Any),
                                 purpose : String?) : JSON::Any?
      if exp = rails["exp"]?.try(&.as_s?)
        return nil if Time.utc >= Time::Format::RFC_3339.parse(exp)
      end
      return nil unless rails["pur"]?.try(&.as_s?) == purpose
      if message = rails["data"]?
        message
      elsif legacy = rails["message"]?.try(&.as_s?)
        # legacy-конверт AS 7.0/standalone: strict-b64(json)
        JSON.parse(decode_strict(legacy))
      end
    end

    private def expiry_string(expires_in : Time::Span?, expires_at : Time?) : String?
      if at = expires_at
        at.to_utc
      elsif span = expires_in
        Time.utc + span
      end.try &.to_s("%Y-%m-%dT%H:%M:%S.%LZ")
    end

    private def json_dump(value : MetadataPayload, io : IO) : Nil
      case value
      when String then value.to_json(io)
      when Int32, Int64 then value.to_s(io)
      when Bool then io << (value ? "true" : "false")
      when Nil then io << "null"
      when Array
        io << "["
        value.each_with_index do |v, i|
          io << "," if i > 0
          v.to_s.to_json(io)
        end
        io << "]"
      when Hash
        io << "{"
        first = true
        value.each do |k, v|
          io << "," unless first
          first = false
          k.to_json(io)
          io << ":"
          json_dump(v, io)
        end
        io << "}"
      end
    end

    private def encode(data : Bytes) : String
      if @url_safe
        Base64.urlsafe_encode(data, padding: false)
      else
        Base64.strict_encode(data)
      end
    end

    # Терпимо к обоим алфавитам (как MessageVerifier#decode).
    private def decode(encoded : String) : Bytes
      Base64.decode(pad(encoded.tr("-_", "+/")))
    end

    private def decode_strict(encoded : String) : String
      Base64.decode_string(pad(encoded.tr("-_", "+/")))
    end

    private def pad(s : String) : String
      s + "=" * ((4 - s.size % 4) % 4)
    end

    # Разбор по длинам закодированных частей справа налево — как в геме
    # (urlsafe-алфавит содержит "-", поэтому простой split небезопасен).
    private def extract_parts(message : String) : {Bytes, Bytes, Bytes}
      rindex = message.size
      tag = extract_part(message, rindex, encoded_len(AUTH_TAG_LENGTH))
      rindex -= SEPARATOR.size + encoded_len(AUTH_TAG_LENGTH)
      iv = extract_part(message, rindex, encoded_len(self.class.iv_len(@cipher)))
      rindex -= SEPARATOR.size + encoded_len(self.class.iv_len(@cipher))
      data = message[0, rindex]
      {decode(data), decode(iv), decode(tag)}
    end

    private def extract_part(message : String, rindex : Int32, length : Int32) : String
      index = rindex - length
      if index >= SEPARATOR.size &&
         message[index - SEPARATOR.size, SEPARATOR.size] == SEPARATOR
        message[index, length]
      else
        raise InvalidMessage.new("missing separator")
      end
    end

    private def encoded_len(n : Int32) : Int32
      if @url_safe
        (4 * n + 2) // 3 # без padding
      else
        4 * ((n + 2) // 3) # с padding
      end
    end

    # AES-*-GCM через EVP: у OpenSSL::Cipher нет auth_tag/auth_data.
    private module AEAD
      def self.encrypt(cipher : String, key : Bytes, iv : Bytes, data : Bytes) : {Bytes, Bytes}
        evp = LibCrypto.evp_get_cipherbyname(cipher)
        ctx = LibCrypto.evp_cipher_ctx_new
        buf = Bytes.new(data.size + 16)
        outl = 0
        begin
          ok = LibCrypto.evp_cipherinit_ex(ctx, evp, nil, key, iv, 1)
          ok = LibCrypto.evp_cipherupdate(ctx, buf, pointerof(outl), data, data.size) if ok == 1
          finl = 0
          ok = LibCrypto.evp_cipherfinal_ex(ctx, buf + outl, pointerof(finl)) if ok == 1
          tag = Bytes.new(AUTH_TAG_LENGTH)
          ok = LibCrypto.evp_cipherctx_ctrl(ctx, LibCrypto::CTRL_GCM_GET_TAG, AUTH_TAG_LENGTH, tag) if ok == 1
          raise OpenSSL::Error.new("encrypt failed") unless ok == 1
          {buf[0, outl + finl], tag}
        ensure
          LibCrypto.evp_cipher_ctx_free(ctx)
        end
      end

      def self.decrypt(cipher : String, key : Bytes, iv : Bytes, tag : Bytes, data : Bytes) : Bytes?
        return nil unless tag.size == AUTH_TAG_LENGTH
        evp = LibCrypto.evp_get_cipherbyname(cipher)
        ctx = LibCrypto.evp_cipher_ctx_new
        buf = Bytes.new(data.size + 16)
        outl = 0
        begin
          ok = LibCrypto.evp_cipherinit_ex(ctx, evp, nil, key, iv, 0)
          ok = LibCrypto.evp_cipherctx_ctrl(ctx, LibCrypto::CTRL_GCM_SET_TAG, tag.size, tag.to_unsafe.as(Void*)) if ok == 1
          ok = LibCrypto.evp_cipherupdate(ctx, buf, pointerof(outl), data, data.size) if ok == 1
          finl = 0
          ok = LibCrypto.evp_cipherfinal_ex(ctx, buf + outl, pointerof(finl)) if ok == 1
          return nil unless ok == 1
          buf[0, outl + finl]
        ensure
          LibCrypto.evp_cipher_ctx_free(ctx)
        end
      end
    end
  end
end
