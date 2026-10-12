# Cache stores spec (Iteration 7):
# 1) oracle mirror — cache_stores_expected.yml captured from real
#    ActiveSupport 8.1.4 RedisCacheStore + redis-server
#    (oracle/cache_stores_cases.rb)
# 2) the shared port contract (cache_store_contract.cr) run for
#    memory/file/pg/redis stores.
# Requires local PostgreSQL and Redis; those parts skip when absent.

require "spec"
require "../src/active_support_cr"
require "./cache_store_contract"
require "../src/adapters/redis_cache"
require "../src/adapters/pg_cache"

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/cache_stores_expected.yml").each_line do |line|
    id, value = line.split('\t', 2)
    hash[id] = value.chomp
  end
  hash
end

REDIS_OK = begin
  `redis-cli -u #{ENV.fetch("REDIS_URL_TEST", "redis://127.0.0.1:6379/15")} ping 2>/dev/null` \
    .strip == "PONG"
rescue ex
  false
end

PG_CACHE_OK = begin
  admin = DB.open(ENV.fetch("CACHE_ADMIN_URL", "postgres:///postgres"))
  admin.exec("DROP DATABASE IF EXISTS crails_cache_spec")
  admin.exec("CREATE DATABASE crails_cache_spec")
  admin.close
  true
rescue ex
  false
end

REDIS_URL = ENV.fetch("REDIS_URL_TEST", "redis://127.0.0.1:6379/15")
REDIS_STORE = REDIS_OK ? ActiveSupport::Cache::RedisCacheStore.new(url: REDIS_URL) : nil
REDIS_NS_STORE = REDIS_OK ? ActiveSupport::Cache::RedisCacheStore.new(url: REDIS_URL, namespace: "ns") : nil

def redis_store
  REDIS_STORE.not_nil!
end

def redis_ns_store
  REDIS_NS_STORE.not_nil!
end

def cache_case(id, result)
  it id do
    result.inspect.should eq EXPECTED[id]
  end
end

if REDIS_OK
  describe ActiveSupport::Cache::RedisCacheStore do
    before_each do
      redis_store.clear
      redis_ns_store.clear
    end

    cache_case "cache_write_read", begin
      redis_store.write("k1", "v1")
      redis_store.read("k1")
    end

    cache_case "cache_read_missing", redis_store.read("nope")

    cache_case "cache_exist", begin
      redis_store.write("k2", "v")
      [redis_store.exist?("k2"), redis_store.exist?("nope")]
    end

    cache_case "cache_delete", begin
      redis_store.write("k3", "v")
      redis_store.delete("k3")
      redis_store.read("k3")
    end

    cache_case "cache_fetch_hit", begin
      redis_store.write("k4", "cached")
      hits = [] of String
      redis_store.fetch("k4") { hits << "miss"; "computed" }
      redis_store.fetch("k5") { hits << "miss5"; "computed5" }
      [hits.join(","), redis_store.read("k4"), redis_store.read("k5")]
    end

    cache_case "cache_increment", begin
      [redis_store.increment("c1"), redis_store.increment("c1"),
       redis_store.increment("c1", 5), redis_store.decrement("c1", 2)]
    end

    # Documented deviation: Rails' RedisCacheStore coder-wraps written
    # values, so INCR on a `write`-created entry fails → nil. Our stores
    # keep raw string values (P0, see redis_cache.cr header) and count
    # integer-parsable entries: 10 → 11.
    it "cache_increment_init (documented deviation)" do
      redis_store.write("c2", "10")
      redis_store.increment("c2").should eq 11
      redis_store.read("c2").should eq "11"
    end

    cache_case "cache_expiry", begin
      redis_store.write("e1", "v", expires_in: 1.seconds)
      before = redis_store.read("e1")
      sleep 1.3
      [before, redis_store.read("e1"), redis_store.exist?("e1")]
    end

    cache_case "cache_namespace", begin
      redis_ns_store.write("nk", "nv")
      [redis_ns_store.read("nk"), redis_store.read("nk"),
       redis_store.keys("ns:*").sort]
    end

    cache_case "cache_clear", begin
      redis_store.write("x1", "1")
      redis_store.write("x2", "2")
      redis_store.clear
      [redis_store.read("x1"), redis_store.read("x2")]
    end
  end

  CacheStoreContract.assert_contract(
    ->{ ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL_TEST", "redis://127.0.0.1:6379/15")) },
    "RedisCacheStore", "redis")
else
  it "redis cache store (requires redis-server)" do
    pending "redis-server not available"
  end
end

PG_CACHE_URL = ENV.fetch("CACHE_DB_URL", "postgres:///crails_cache_spec")
PG_STORE = PG_CACHE_OK ? ActiveSupport::Cache::SolidCacheStore.connect(PG_CACHE_URL) : nil

def pg_store
  PG_STORE.not_nil!
end

if PG_CACHE_OK

  CacheStoreContract.assert_contract(
    ->{ ActiveSupport::Cache::SolidCacheStore.connect(ENV.fetch("CACHE_DB_URL", "postgres:///crails_cache_spec")) },
    "SolidCacheStore", "pg")

  describe ActiveSupport::Cache::SolidCacheStore do
    it "prunes expired entries (delete_expired)" do
      pg_store.clear
      pg_store.write("prune", "v", expires_in: 0.1.seconds)
      sleep 0.2
      pg_store.read("prune").should be_nil
      pg_store.delete_expired
      pg_store.db.scalar("SELECT count(*)::bigint FROM solid_cache_entries").as(Int64).should eq 0
    end
  end
else
  it "pg cache store (requires PostgreSQL)" do
    pending "PostgreSQL not available"
  end
end

CacheStoreContract.assert_contract(
  ->{ ActiveSupport::Cache::MemoryStore.new },
  "MemoryStore", "memory")

CacheStoreContract.assert_contract(
  ->{ ActiveSupport::Cache::FileStore.new("#{__DIR__}/tmp/file-contract") },
  "FileStore", "file")
