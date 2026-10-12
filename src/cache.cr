# ActiveSupport::Cache — Rails cache stores (P0: MemoryStore, FileStore).
#
# Values are Strings in P0 (object marshalling lands with active_record).
# Rails API: read/write/fetch/exist?/delete/clear/increment/decrement,
# expires_in, lookup_store(:memory_store | :file_store, path:).

module ActiveSupport
  module Cache
    class Entry
      getter value : String
      getter expires_at : Time?
      getter created_at : Time

      def initialize(@value : String, expires_in : Time::Span? = nil, *, expires_at : Time? = nil)
        @created_at = Time.local
        @expires_at = expires_at || (expires_in ? Time.local + expires_in : nil)
      end

      def expired? : Bool
        exp = @expires_at
        !exp.nil? && exp <= Time.local
      end
    end

    # Hexagonal port (Iteration 7): the narrow seam every cache store is
    # written against. The 1:1 Rails API stays on `Store`, which includes
    # this port; PG/Redis adapters implement only these four operations.
    module CacheStore
      abstract def lookup(name : String) : Entry?
      abstract def store(name : String, entry : Entry) : Nil
      abstract def remove(name : String) : Nil
      abstract def clear : Nil
    end

    abstract class Store
      include CacheStore
      def read(name : String) : String?
        entry = lookup(name)
        return nil unless entry
        return nil if entry.expired?
        entry.value
      end

      def write(name : String, value : String, expires_in : Time::Span? = nil) : Nil
        store(name, Entry.new(value, expires_in))
      end

      def fetch(name : String, expires_in : Time::Span? = nil, &block : -> String) : String
        cached = read(name)
        return cached unless cached.nil?
        value = block.call
        write(name, value, expires_in: expires_in)
        value
      end

      def exist?(name : String) : Bool
        !read(name).nil?
      end

      def delete(name : String) : Nil
        remove(name)
      end

      abstract def lookup(name : String) : Entry?
      abstract def store(name : String, entry : Entry) : Nil
      abstract def remove(name : String) : Nil
      abstract def clear : Nil

      # Rails semantics: increment on an existing, unexpired entry keeps
      # the entry's original expiry (fixed window from the first write —
      # verified against AS 8.1.4 oracle, rate_limit cases). A new entry
      # gets the passed expires_in. Returns nil only when the store
      # cannot increment (NullStore) — rate limiting is disabled then.
      def increment(name : String, amount : Int32 = 1, expires_in : Time::Span? = nil) : Int32?
        if (entry = lookup(name)) && !entry.expired?
          value = (entry.value.to_i? || 0) + amount
          store(name, Entry.new(value.to_s, expires_at: entry.expires_at))
          value
        else
          value = amount
          store(name, Entry.new(value.to_s, expires_in: expires_in))
          value
        end
      end

      def decrement(name : String, amount : Int32 = 1, expires_in : Time::Span? = nil) : Int32?
        increment(name, -amount, expires_in)
      end
    end

    class MemoryStore < Store
      def initialize(@options = {} of String => String)
        @entries = {} of String => Entry
      end

      def lookup(name : String) : Entry?
        @entries[name]?
      end

      def store(name : String, entry : Entry) : Nil
        @entries[name] = entry
      end

      def remove(name : String) : Nil
        @entries.delete(name)
      end

      def clear : Nil
        @entries.clear
      end
    end

    class FileStore < Store
      getter directory : String

      # Sub-second precision: expiry spans below 1s must survive the
      # roundtrip (ISO_8601_DATE_TIME truncates to whole seconds).
      TIME_FORMAT = Time::Format.new("%FT%T.%6N%:z")

      def initialize(@directory : String)
        Dir.mkdir_p(@directory)
      end

      def lookup(name : String) : Entry?
        path = file_path(name)
        return nil unless File.exists?(path)
        raw = File.read(path)
        value, expires_at = raw.split('\n', 2, remove_empty: false)
        exp = expires_at.strip.empty? ? nil : TIME_FORMAT.parse(expires_at.strip)
        return nil if exp && exp <= Time.local
        Entry.new(value)
      rescue ex : Time::Format::Error | ArgumentError
        nil
      end

      def store(name : String, entry : Entry) : Nil
        path = file_path(name)
        Dir.mkdir_p(File.dirname(path))
        exp = entry.expires_at.try { |e| TIME_FORMAT.format(e) }
        File.write(path, "#{entry.value}\n#{exp || ""}")
      end

      def remove(name : String) : Nil
        path = file_path(name)
        File.delete(path) if File.exists?(path)
      end

      def clear : Nil
        Dir.glob(File.join(@directory, "**", "*")).each do |path|
          File.delete(path) if File.file?(path)
        end
      end

      private def file_path(name : String) : String
        hashed = name.gsub('/', "--")
        File.join(@directory, "#{hashed}.cache")
      end
    end

    # Rails NullStore: caches nothing. read → nil, increment → nil
    # (which disables Rails-style rate limiting, oracle null_store case).
    class NullStore < Store
      def lookup(name : String) : Entry?
        nil
      end

      def store(name : String, entry : Entry) : Nil
      end

      def remove(name : String) : Nil
      end

      def clear : Nil
      end
    end

    def self.lookup_store(store : Symbol, path : String = "tmp/cache") : Store
      case store
      when :memory_store then MemoryStore.new
      when :file_store   then FileStore.new(path)
      when :null_store   then NullStore.new
      else raise ArgumentError.new("unknown cache store: #{store}")
      end
    end
  end
end
