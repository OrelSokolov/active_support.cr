# ActiveSupport::KeyGenerator — порт AS 8.1.4
# (lib/active_support/key_generator.rb): обёртка над PBKDF2-HMAC.
# Дефолты гема: SHA1, 2**16 итераций, ключ 64 байта. Детерминирован —
# побайтово совместим (оракул oracle/crypto_cases.rb, kg_* / ckg_*).
#
# ActiveSupport::CachingKeyGenerator — мемоизация по "salt|key_size".

require "openssl/pkcs5"

module ActiveSupport
  class KeyGenerator
    def initialize(@secret : String, iterations : Int32 = 2**16,
                   @digest : OpenSSL::Algorithm = :sha1)
      @iterations = iterations
    end

    def generate_key(salt : String, key_size : Int32 = 64) : Bytes
      OpenSSL::PKCS5.pbkdf2_hmac(@secret, salt, @iterations, @digest,
        key_size: key_size)
    end
  end

  class CachingKeyGenerator
    def initialize(@key_generator : KeyGenerator)
      @cache_keys = {} of String => Bytes
    end

    def generate_key(salt : String, key_size : Int32 = 64) : Bytes
      @cache_keys["#{salt}|#{key_size}"] ||= @key_generator.generate_key(salt, key_size)
    end
  end
end
