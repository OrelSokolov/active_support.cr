# ActiveSupport::Cache::SolidCacheStore — PG-backed store behind the
# CacheStore port, the analog of Rails 8's solid_cache (a dedicated
# table instead of the Rails shared-cache database). Same schema shape:
# (key, value, expires_at). Counters are atomic in SQL (the redis-store
# deviation note in redis_cache.cr applies here too).

require "pg"

module ActiveSupport
  module Cache
    class SolidCacheStore < Store
      getter db : DB::Database

      def initialize(@db : DB::Database)
        ensure_schema
      end

      def self.connect(url : String = ENV.fetch("DATABASE_URL", "postgres:///")) : SolidCacheStore
        new(DB.open(url))
      end

      def lookup(name : String) : Entry?
        value = @db.query_one?(<<-SQL, name, as: String)
          SELECT value FROM solid_cache_entries
          WHERE key = $1 AND (expires_at IS NULL OR expires_at > now())
        SQL
        value ? Entry.new(value) : nil
      end

      def store(name : String, entry : Entry) : Nil
        sql = <<-SQL
          INSERT INTO solid_cache_entries (key, value, expires_at)
          VALUES ($1, $2, $3::timestamptz)
          ON CONFLICT (key) DO UPDATE SET value = $2, expires_at = $3::timestamptz
        SQL
        @db.exec(sql, name, entry.value, entry.expires_at.try(&.to_utc))
      end

      def remove(name : String) : Nil
        @db.exec("DELETE FROM solid_cache_entries WHERE key = $1", name)
      end

      def clear : Nil
        @db.exec("DELETE FROM solid_cache_entries")
      end

      def increment(name : String, amount : Int32 = 1, expires_in : Time::Span? = nil) : Int32?
        expires_at = expires_in ? Time.utc + expires_in : nil
        sql = <<-SQL
          INSERT INTO solid_cache_entries (key, value, expires_at)
          VALUES ($1, $2::text, $3::timestamptz)
          ON CONFLICT (key) DO UPDATE SET
            value = CASE WHEN solid_cache_entries.expires_at IS NULL
                            OR solid_cache_entries.expires_at > now()
                        THEN (solid_cache_entries.value::bigint + $2::bigint)::text
                        ELSE $2::text END,
            expires_at = $3::timestamptz
          RETURNING value::bigint
        SQL
        @db.scalar(sql, name, amount.to_s, expires_at).as(Int64).to_i
      rescue ex
        nil
      end

      def decrement(name : String, amount : Int32 = 1, expires_in : Time::Span? = nil) : Int32?
        increment(name, -amount, expires_in)
      end

      # Maintenance: drop expired rows (solid_cache's pruning job).
      def delete_expired : Nil
        @db.exec("DELETE FROM solid_cache_entries WHERE expires_at <= now()")
      end

      def ensure_schema : Nil
        @db.exec(<<-SQL)
          CREATE TABLE IF NOT EXISTS solid_cache_entries (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            expires_at TIMESTAMPTZ,
            created_at TIMESTAMPTZ NOT NULL DEFAULT now()
          )
        SQL
        @db.exec(<<-SQL)
          CREATE INDEX IF NOT EXISTS solid_cache_entries_expiry_idx
          ON solid_cache_entries (expires_at)
        SQL
      end
    end
  end
end
