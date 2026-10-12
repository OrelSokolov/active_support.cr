# Oracle cases for cache stores (Iteration 7).
#
# Run against the ORIGINAL gems (activesupport 8.1.4 RedisCacheStore,
# real redis-server):
#   TZ=UTC ruby oracle/cache_stores_cases.rb > oracle/cache_stores_expected.yml
#
# Each line: "<case_id>\t<value>". Mirrored 1:1 in spec/cache_stores_spec.cr.
# RedisCacheStore is the only Rails built-in network store — the same
# contract semantics are what our PG/Redis/memory/file stores must
# reproduce (the PG store's solid_cache analog keeps the Store API).

ENV["TZ"] = "UTC"

gem "activesupport", "= 8.1.4"
gem "redis", "= 5.4.1"

require "active_support"
require "active_support/cache"
require "redis"

def render(v)
  v.inspect
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

REDIS_URL = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/15")
STORE = ActiveSupport::Cache::RedisCacheStore.new(url: REDIS_URL, namespace: nil)
NS_STORE = ActiveSupport::Cache::RedisCacheStore.new(url: REDIS_URL, namespace: "ns")

def fresh
  STORE.clear
  NS_STORE.clear
end

fresh

case_run "cache_write_read" do
  STORE.write("k1", "v1")
  STORE.read("k1")
end

case_run "cache_read_missing" do
  STORE.read("nope")
end

case_run "cache_exist" do
  STORE.write("k2", "v")
  [STORE.exist?("k2"), STORE.exist?("nope")]
end

case_run "cache_delete" do
  STORE.write("k3", "v")
  STORE.delete("k3")
  STORE.read("k3")
end

case_run "cache_fetch_hit" do
  STORE.write("k4", "cached")
  hits = []
  STORE.fetch("k4") { hits << "miss"; "computed" }
  STORE.fetch("k5") { hits << "miss5"; "computed5" }
  [hits.join(","), STORE.read("k4"), STORE.read("k5")]
end

case_run "cache_increment" do
  fresh
  [STORE.increment("c1"), STORE.increment("c1"), STORE.increment("c1", 5),
   STORE.decrement("c1", 2)]
end

case_run "cache_increment_init" do
  fresh
  STORE.write("c2", 10)
  [STORE.increment("c2"), STORE.read("c2")]
end

case_run "cache_expiry" do
  fresh
  STORE.write("e1", "v", expires_in: 1)
  before = STORE.read("e1")
  sleep 1.3
  [before, STORE.read("e1"), STORE.exist?("e1")]
end

case_run "cache_namespace" do
  fresh
  NS_STORE.write("nk", "nv")
  [NS_STORE.read("nk"), STORE.read("nk"),
   REDIS_NAMESPACE_KEYS = Redis.new(url: REDIS_URL).keys("ns:*").sort]
end

case_run "cache_clear" do
  fresh
  STORE.write("x1", "1")
  STORE.write("x2", "2")
  STORE.clear
  [STORE.read("x1"), STORE.read("x2")]
end
