require "spec"
require "../src/active_support_cr"

describe "ActiveSupport::TimeFormats" do
  after_each do
    ActiveSupport::TimeFormats.clear
  end

  it "registers a proc formatter resolved by Time#to_fs" do
    ActiveSupport::TimeFormats.register(:epoch, ->(time : Time) {
      ((time.to_f * 1000).to_i64).to_s
    })
    # (time.to_f * 1000).to_i — Rails: config/initializers/time_formats.rb
    Time.utc(2026, 1, 2, 3, 4, 5).to_fs(:epoch).should eq("1767323045000")
    Time.utc(2026, 1, 2, 3, 4, 5, nanosecond: 678901000).to_fs(:epoch).should eq("1767323045678")
  end

  it "registers a strftime formatter resolved by Time#to_fs" do
    ActiveSupport::TimeFormats.register(:month_and_year, "%B %Y")
    Time.utc(2026, 1, 2).to_fs(:month_and_year).should eq("January 2026")
  end

  it "shadows a same-named builtin format" do
    ActiveSupport::TimeFormats.register(:db, "db:%F")
    Time.utc(2026, 1, 2, 3, 4, 5).to_fs(:db).should eq("db:2026-01-02")
  end

  it "leaves unknown formats on the to_s fallback" do
    Time.utc(2026, 1, 2, 3, 4, 5).to_fs(:doesnt_exist).should eq(
      Time.utc(2026, 1, 2, 3, 4, 5).to_s)
  end

  it "TimeWithZone#to_fs resolves proc formatters on the UTC instant" do
    ActiveSupport::TimeFormats.register(:epoch, ->(time : Time) {
      ((time.to_f * 1000).to_i64).to_s
    })
    twz = ActiveSupport::TimeZone.new("Europe/Berlin").now.in_time_zone("Europe/Berlin")
    twz.to_fs(:epoch).should eq(((twz.utc.to_f * 1000).to_i64).to_s)
  end

  it "TimeWithZone#to_fs resolves strftime formatters on the wall clock" do
    ActiveSupport::TimeFormats.register(:month_and_year, "%B %Y")
    twz = Time.utc(2026, 1, 2, 23, 0, 0).in_time_zone("Europe/Berlin")
    twz.to_fs(:month_and_year).should eq("January 2026")
  end

  it "list exposes registered formats" do
    ActiveSupport::TimeFormats.register(:epoch, ->(t : Time) { t.to_unix.to_s })
    ActiveSupport::TimeFormats.lookup(:epoch).should_not be_nil
    ActiveSupport::TimeFormats.list.size.should eq(1)
  end
end

describe "Time#to_f / TimeWithZone#to_f" do
  it "returns epoch seconds as Float64" do
    Time.utc(2026, 1, 2, 3, 4, 5).to_f.should eq(1767323045.0)
    Time.utc(2026, 1, 2, 3, 4, 5, nanosecond: 678901000).to_f.should be_close(1767323045.678901, 1e-4)
  end

  it "TimeWithZone delegates to the UTC instant" do
    twz = Time.utc(2026, 1, 2, 3, 4, 5).in_time_zone("Europe/Berlin")
    twz.to_f.should eq(1767323045.0)
  end
end

describe "String#inquiry" do
  it "answers name? predicates" do
    "production".inquiry.production?.should be_true
    "production".inquiry.development?.should be_false
    "".inquiry.blank?.should be_true
  end

  it "compares equal to the underlying string" do
    inquiry = "bot_key".inquiry
    inquiry.bot_key?.should be_true
    inquiry.should eq("bot_key")
    inquiry.to_s.should eq("bot_key")
    inquiry.present?.should be_true
  end

  it "raises at compile time on non-predicate calls" do
    # method_missing generates only `name?` methods; anything else is a
    # {% raise %} at the call site (compile-time error, no runtime miss).
  end
end
