require "spec"
require "file_utils"
require "../src/active_support_cr"

describe "ActiveSupport::Cache" do
  describe "MemoryStore" do
    it "write/read/exist?/delete" do
      cache = ActiveSupport::Cache::MemoryStore.new
      cache.write("a", "1")
      cache.read("a").should eq("1")
      cache.exist?("a").should be_true
      cache.delete("a")
      cache.exist?("a").should be_false
      cache.read("a").should be_nil
    end

    it "fetch caches the block" do
      cache = ActiveSupport::Cache::MemoryStore.new
      calls = 0
      v1 = cache.fetch("k") { calls += 1; "computed" }
      v2 = cache.fetch("k") { calls += 1; "other" }
      v1.should eq("computed")
      v2.should eq("computed")
      calls.should eq(1)
    end

    it "expires entries after expires_in" do
      cache = ActiveSupport::Cache::MemoryStore.new
      cache.write("exp", "x", expires_in: 1.milliseconds)
      cache.read("exp").should eq("x")
      sleep 5.milliseconds
      cache.read("exp").should be_nil
    end

    it "increment/decrement" do
      cache = ActiveSupport::Cache::MemoryStore.new
      cache.increment("hits").should eq(1)
      cache.increment("hits", 4).should eq(5)
      cache.decrement("hits", 2).should eq(3)
      cache.read("hits").should eq("3")
    end

    it "lookup_store(:memory_store)" do
      store = ActiveSupport::Cache.lookup_store(:memory_store)
      store.should be_a(ActiveSupport::Cache::MemoryStore)
    end
  end

  describe "FileStore" do
    it "persists across store instances" do
      dir = File.join(Dir.tempdir, "as_cache_spec_#{Random::Secure.hex(4)}")
      cache = ActiveSupport::Cache::FileStore.new(dir)
      cache.write("nested/key", "value")
      cache.read("nested/key").should eq("value")

      reopened = ActiveSupport::Cache::FileStore.new(dir)
      reopened.read("nested/key").should eq("value")
      reopened.exist?("nested/key").should be_true
      reopened.delete("nested/key")
      reopened.read("nested/key").should be_nil
    ensure
      if (d = dir) && Dir.exists?(d)
        FileUtils.rm_r(d)
      end
    end

    it "respects expires_in after reopen" do
      dir = File.join(Dir.tempdir, "as_cache_spec_#{Random::Secure.hex(4)}")
      cache = ActiveSupport::Cache::FileStore.new(dir)
      cache.write("exp", "x", expires_in: 1.milliseconds)
      sleep 5.milliseconds
      ActiveSupport::Cache::FileStore.new(dir).read("exp").should be_nil
    ensure
      if (d = dir) && Dir.exists?(d)
        FileUtils.rm_r(d)
      end
    end
  end
end
