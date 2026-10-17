# ActiveSupport::MessageVerifier — подписанные значения, формат байт-в-байт
# с AS 8.1.4 (serializer: JSON, digest: SHA256):
#   Base64.strict_encode64(json) + "--" + hexdigest(hmac_sha256)
#
# Формат с метаданными (purpose/exp — как в Rails 8.1 приложениях,
# `use_message_serializer_for_metadata`):
#   urlsafe_b64_nopad(json({"_rails":{"data":<json>,"exp":<iso8601(3)>,
#                                    "pur":<purpose>}})) + "--" + hexdigest
# Чтение принимает оба конверта — и `data`-конверт, и legacy
# `{"_rails":{"message":<b64(json)>,"exp":null,...}}` (standalone-гем),
# как и сам Rails (Metadata#deserialize_with_metadata).
#
# Опция `force_legacy_metadata_serializer: true` (имя — как в гемe):
# ПИСАТЬ legacy-конверт `{"_rails":{"message":strict_b64(json),
# "exp":<iso8601(3)|null>,"pur":<purpose|null>}}` — так устроены
# signed/encrypted cookies actionpack 8.1.4 (verifier/encryptor с
# NullSerializer не входит в ENVELOPE_SERIALIZERS, поэтому приложение
# всегда пишет legacy-конверт) — оракул action_pack.cr/oracle/cookies_*.
# Опция `digest:` (дефолт гемa — SHA1, здесь SHA256 ради обратной
# совместимости порта) задаёт HMAC-дайджест подписи.
#
# Оракулы: turbo.cr/oracle/cases.rb (verifier_*, stream_name_* — формат
# без метаданных), active_storage.cr/oracle/cases_signed_id.rb
# (sid_* / disk_* — формат с purpose: signed_id блоба, токены Disk-сервиса).

require "base64"
require "crypto/subtle"
require "json"
require "openssl/hmac"

module ActiveSupport
  # Готовый JSON-фрагмент для подписи payloads со вложенными структурами
  # (variation-ключи ActiveStorage: {"format":"png","resize_to_limit":
  # [1200,800]}) — дампится в конверт как есть, без строкового экранирования.
  class RawJSON
    getter json : String

    def initialize(@json : String)
    end
  end

  class MessageVerifier
    # Значение, сериализуемое в JSON-конверт метаданных (payload токенов
    # Disk-сервиса — хеш со скалярами; id для signed_id — целое).
    alias MetadataScalar = String | Int32 | Int64 | Bool | Nil
    alias MetadataPayload = String | Int32 | Int64 | Bool | Nil |
                            Array(String | Symbol) |
                            Hash(String, MetadataScalar) |
                            RawJSON

    class InvalidSignature < Exception
    end

    @digest : OpenSSL::Algorithm

    def initialize(@secret : String | Bytes, @url_safe : Bool = false,
                   digest : Symbol = :sha256,
                   force_legacy_metadata_serializer : Bool = false)
      @digest = case digest
                when :sha1   then OpenSSL::Algorithm::SHA1
                when :sha256 then OpenSSL::Algorithm::SHA256
                else
                  raise ArgumentError.new("unsupported digest #{digest}")
                end
      @force_legacy_metadata = force_legacy_metadata_serializer
    end

    # Подписывает значение. Без purpose/exp — формат как в AS 8.1.4 для
    # голых сообщений: b64(json) + "--" + HEXdigest (turbo-оракул). С
    # purpose/exp — data-конверт Rails 8.1 (url_safe=true для wire-совмес-
    # тимости с signed_id блобов: base64url без padding).
    def generate(value : MetadataPayload, purpose : String? = nil,
                 expires_in : Time::Span? = nil,
                 expires_at : Time? = nil) : String
      if purpose || expires_in || expires_at
        expiry = expiry_string(expires_in, expires_at)
        payload =
          if @force_legacy_metadata
            # legacy-конверт (Rails 7.0-семантика; wire signed/encrypted
            # cookies actionpack): message = strict_b64(json), exp/pur
            # присутствуют всегда (null, если не заданы).
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
        payload = String.build { |io| json_dump(value, io) }
      end
      data = @url_safe ? Base64.urlsafe_encode(payload, padding: false)
                       : Base64.strict_encode(payload)
      "#{data}--#{OpenSSL::HMAC.hexdigest(@digest, @secret, data)}"
    end

    # Возвращает исходное значение как JSON::Any, если подпись верна,
    # purpose совпадает и срок не истёк; иначе nil. Понимает оба конверта.
    def verified_any(signed_message : String,
                     purpose : String? = nil) : JSON::Any?
      hex_len = case @digest
                in OpenSSL::Algorithm::SHA1   then 40
                in OpenSSL::Algorithm::SHA256 then 64
                in OpenSSL::Algorithm then 0
                end
      return nil unless signed_message.size > hex_len + 2
      sep = signed_message.size - hex_len - 2
      return nil unless signed_message[sep, 2] == "--"
      data = signed_message[0, sep]
      digest = signed_message[sep + 2..]
      expected = OpenSSL::HMAC.hexdigest(@digest, @secret, data)
      return nil unless Crypto::Subtle.constant_time_compare(expected, digest)

      json = decode(data)
      parsed = JSON.parse(json)
      if envelope = parsed.as_h?.try(&.["_rails"]?).try(&.as_h?)
        extract_envelope(envelope, purpose)
      else
        # Голое сообщение: с ожидаемым purpose не совпадает (как в Rails).
        return nil if purpose
        parsed
      end
    rescue ArgumentError | Base64::Error | JSON::ParseException | IO::Error
      nil
    end

    # Возвращает исходную строку, если подпись верна; иначе nil.
    # (Для полезных нагрузок turbo это всегда String — имя стрима.)
    def verified(signed_message : String) : String?
      value = verified_any(signed_message)
      value.try(&.as_s?)
    end

    # Подписывает Marshal-строку в legacy-конверте метаданных — wire-формат
    # SignedGlobalID (globalid 1.4 / Rails to_sgid с дефолтным Marshal-
    # сериализатором): {"_rails":{"message":strict_b64(marshal),"exp":…,
    # "pur":…}}. exp/pur присутствуют всегда (как у standalone-гема).
    def generate_marshaled(value : String, purpose : String? = nil,
                           expires_at : Time? = nil) : String
      expiry = expiry_string(nil, expires_at)
      payload = String.build do |io|
        io << "{\"_rails\":{\"message\":"
        Base64.strict_encode(ActiveSupport::MarshalString.dump(value)).to_json(io)
        io << ",\"exp\":" << (expiry ? expiry.to_json : "null")
        io << ",\"pur\":" << (purpose ? purpose.to_json : "null")
        io << "}}"
      end
      data = @url_safe ? Base64.urlsafe_encode(payload, padding: false)
                       : Base64.strict_encode(payload)
      "#{data}--#{OpenSSL::HMAC.hexdigest(@digest, @secret, data)}"
    end

    # Проверяет подпись и возвращает Marshal-строку из конверта
    # #generate_marshaled; иначе nil.
    def verified_marshaled(signed_message : String,
                           purpose : String? = nil) : String?
      hex_len = case @digest
                in OpenSSL::Algorithm::SHA1   then 40
                in OpenSSL::Algorithm::SHA256 then 64
                in OpenSSL::Algorithm then 0
                end
      return nil unless signed_message.size > hex_len + 2
      sep = signed_message.size - hex_len - 2
      return nil unless signed_message[sep, 2] == "--"
      data = signed_message[0, sep]
      digest = signed_message[sep + 2..]
      expected = OpenSSL::HMAC.hexdigest(@digest, @secret, data)
      return nil unless Crypto::Subtle.constant_time_compare(expected, digest)

      parsed = JSON.parse(decode(data))
      envelope = parsed.as_h?.try(&.["_rails"]?).try(&.as_h?) || return nil
      if exp = envelope["exp"]?.try(&.as_s?)
        return nil if Time.utc >= parse_expiry(exp)
      end
      return nil unless envelope["pur"]?.try(&.as_s?) == purpose
      legacy = envelope["message"]?.try(&.as_s?) || return nil
      MarshalString.load(decode_strict(legacy))
    rescue ArgumentError | Base64::Error | JSON::ParseException | IO::Error
      nil
    end

    # --- внутреннее -----------------------------------------------------

    private def extract_envelope(rails : Hash(String, JSON::Any),
                                 purpose : String?) : JSON::Any?
      if exp = rails["exp"]?.try(&.as_s?)
        return nil if Time.utc >= parse_expiry(exp)
      end
      return nil unless rails["pur"]?.try(&.as_s?) == purpose
      if message = rails["data"]?
        message
      elsif legacy = rails["message"]?.try(&.as_s?)
        # legacy-конверт standalone-гема: сообщение — strict-b64(json)
        JSON.parse(decode_strict(legacy))
      end
    end

    private def parse_expiry(exp : String) : Time
      # iso8601(3), как ActiveSupport::JSON кодирует Time ("...T00:00:00.000Z")
      Time::Format::RFC_3339.parse(exp)
    end

    private def expiry_string(expires_in : Time::Span?, expires_at : Time?) : String?
      if at = expires_at
        at.to_utc
      elsif span = expires_in
        Time.utc + span
      end.try &.to_s("%Y-%m-%dT%H:%M:%S.%LZ")
    end

    # Принимает strict- и urlsafe-алфавит (как MessageVerifier#decode,
    # который при неудаче пробует противоположный url_safe).
    private def decode(encoded : String) : String
      decode_strict(pad(encoded.tr("-_", "+/")))
    end

    private def decode_strict(encoded : String) : String
      Base64.decode_string(pad(encoded))
    end

    private def pad(s : String) : String
      s + "=" * ((4 - s.size % 4) % 4)
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
      when RawJSON then io << value.json
      end
    end
  end
end
