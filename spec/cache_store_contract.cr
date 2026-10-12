# Shared port contract (Iteration 7): every cache store — memory, file,
# PG (SolidCacheStore), Redis — runs this ONE spec against the CacheStore
# port. Rails' own store-behavior tests are per-store; here the contract
# is the common subset all stores must satisfy.

require "spec"
require "../src/active_support_cr"

module CacheStoreContract
  SEED = Random.new(20261003).next_u32

  def self.assert_contract(build : -> ActiveSupport::Cache::Store,
                           name : String, unique : String)
    describe "#{name} (CacheStore port contract)" do
      key = "contract-#{unique}"
      store = build.call

      it "write/read roundtrip" do
        store.write(key, "v1")
        store.read(key).should eq "v1"
      end

      it "read missing → nil" do
        store.read("#{key}-missing").should be_nil
      end

      it "exist?" do
        store.write("#{key}-e", "v")
        store.exist?("#{key}-e").should be_true
        store.exist?("#{key}-missing").should be_false
      end

      it "delete" do
        store.write("#{key}-d", "v")
        store.delete("#{key}-d")
        store.read("#{key}-d").should be_nil
      end

      it "fetch: block only on miss" do
        store.write("#{key}-f", "cached")
        calls = [] of String
        store.fetch("#{key}-f") { calls << "miss1"; "computed1" }.should eq "cached"
        store.fetch("#{key}-f2") { calls << "miss2"; "computed2" }.should eq "computed2"
        calls.should eq ["miss2"]
      end

      it "increment/decrement counters" do
        store.increment("#{key}-c").should eq 1
        store.increment("#{key}-c").should eq 2
        store.increment("#{key}-c", 5).should eq 7
        store.decrement("#{key}-c", 2).should eq 5
      end

      it "expires_in drops the entry" do
        store.write("#{key}-exp", "v", expires_in: 0.2.seconds)
        store.read("#{key}-exp").should eq "v"
        sleep 0.4
        store.read("#{key}-exp").should be_nil
        store.exist?("#{key}-exp").should be_false
      end

      it "clear" do
        store.write("#{key}-x1", "1")
        store.write("#{key}-x2", "2")
        store.clear
        store.read("#{key}-x1").should be_nil
        store.read("#{key}-x2").should be_nil
      end
    end
  end
end
