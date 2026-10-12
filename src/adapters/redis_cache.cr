# ActiveSupport::Cache::RedisCacheStore — Redis adapter behind the
# CacheStore port. Values are raw strings (P0; Rails wraps entries in a
# coder — documented deviation: our stores keep raw string values, so
# `increment` on a `write`-created integer-parsable entry counts it
# instead of returning nil). Counters use native INCRBY.

require "redis"

module ActiveSupport
  module Cache
    class RedisCacheStore < Store
      def initialize(url : String = ENV.fetch("REDIS_URL", "redis:///"),
                     namespace : String? = nil)
        @redis = ::Redis::Client.new(URI.parse(url))
        @namespace = namespace
      end

      def lookup(name : String) : Entry?
        if value = @redis.get(key_for(name))
          Entry.new(value)
        end
      end

      def store(name : String, entry : Entry) : Nil
        full_key = key_for(name)
        if expires = entry.expires_at
          @redis.set(full_key, entry.value, ex: expires - Time.utc)
        else
          @redis.set(full_key, entry.value)
        end
      end

      def remove(name : String) : Nil
        @redis.del(key_for(name))
      end

      def clear : Nil
        @redis.flushdb
      end

      def increment(name : String, amount : Int32 = 1, expires_in : Time::Span? = nil) : Int32?
        full_key = key_for(name)
        value = @redis.incrby(full_key, amount)
        @redis.expire(full_key, expires_in) if expires_in
        value.to_i
      rescue ex
        nil
      end

      def decrement(name : String, amount : Int32 = 1, expires_in : Time::Span? = nil) : Int32?
        increment(name, -amount, expires_in)
      end

      def keys(pattern : String = "*") : Array(String)
        @redis.keys(namespaced(pattern)).map &.to_s
      end

      private def key_for(name : String) : String
        @namespace ? "#{@namespace}:#{name}" : name
      end

      private def namespaced(pattern : String) : String
        @namespace ? "#{@namespace}:#{pattern}" : pattern
      end
    end
  end
end
