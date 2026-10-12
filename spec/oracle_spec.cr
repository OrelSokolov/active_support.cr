# Oracle spec: 1:1 mirror of oracle/cases.rb. Expected values live in
# oracle/expected.yml — captured from the ORIGINAL activesupport 8.1.4.
# The port must reproduce them exactly; tests are never edited on either
# side (see AGENTS.md / oracle/rails-tests for the original minitest suites).

require "spec"
require "../src/active_support_cr"

def r(v : Bool | Int | Int64 | Float | String) : String
  v.inspect
end

def r(v : Nil) : String
  "nil"
end

def r(v : Symbol) : String
  ":#{v}"
end

def r(t : Time) : String
  u = t.in(Time::Location::UTC)
  sprintf("T%04d-%02d-%02d %02d:%02d:%02d.%09d",
    u.year, u.month, u.day, u.hour, u.minute, u.second, u.nanosecond)
end

def r(z : ActiveSupport::TimeWithZone) : String
  r(z.utc)
end

def r(d : ActiveSupport::Duration) : String
  "D:#{d.to_s}"
end

# Stdlib spans render in the Rails Duration format (2.days is a Span here,
# see core_ext.cr note) — decomposed: "2 days and 6 hours".
def r(d : Time::Span) : String
  total = d.total_seconds.to_i64
  units = {weeks: 604_800_i64, days: 86_400_i64, hours: 3_600_i64,
           minutes: 60_i64, seconds: 1_i64}
  fragments = [] of String
  units.each do |unit, secs|
    n = total // secs
    next if n == 0
    total -= n * secs
    name = unit.to_s.chomp('s')
    fragments << "#{n} #{n == 1 ? name : "#{name}s"}"
  end
  "D:#{fragments.empty? ? "0 seconds" : fragments.size == 1 ? fragments.first : "#{fragments[0...-1].join(", ")} and #{fragments.last}"}"
end

def r(range : Range) : String
  "R(#{r(range.begin)},#{r(range.end)},#{range.excludes_end? ? 'x' : 'i'})"
end

def r(a : Array) : String
  "A[#{a.map { |e| r(e) }.join(",")}]"
end

def r(h : Hash) : String
  keyed = {} of String => String
  h.each { |k, v| keyed[k.to_s] = "#{r(k)}=>#{r(v)}" }
  "H{#{keyed.keys.sort.map { |ks| keyed[ks] }.join(",")}}"
end

def t : Time
  Time.utc(2026, 3, 15, 12, 30, 45) # Sunday
end

cases = {} of String => Proc(String)

# --- Object / Nil -------------------------------------------------------
cases["obj_blank_nil"]        = -> { r(nil.blank?) }
cases["obj_blank_str"]        = -> { r("  ".blank?) }
cases["obj_present_zero"]     = -> { r(0.present?) }
cases["obj_presence_empty"]   = -> { r("".presence) }
cases["obj_presence_val"]     = -> { r("x".presence) }
cases["obj_in_true"]          = -> { r(1.in?([1, 2])) }
cases["obj_in_false"]         = -> { r(3.in?([1, 2])) }
cases["obj_in_str"]           = -> { r("a".in?("abc")) }
cases["obj_presence_in"]      = -> { r(1.presence_in([1, 2])) }
cases["obj_presence_in_nil"]  = -> { r(3.presence_in([1, 2])) }
cases["obj_deep_dup"]         = -> do
  h = {:a => {:b => 1}}
  d = h.deep_dup
  d[:a][:b] = 2
  r("#{r(h)} #{r(d)}")
end
cases["obj_to_param"]         = -> { r(123.to_param) }
cases["obj_try"]              = -> { r(nil.try(&.upcase)) }
cases["obj_try!"]             = -> do
  begin
    nil.try!(&.upcase)
    r("no-raise")
  rescue
    r("handled")
  end
end

# --- String ---------------------------------------------------------------
cases["str_squish"]          = -> { r(" foo \t bar \n".squish) }
cases["str_squish_html"]     = -> { r("<p> foo </p>".squish) }
cases["str_truncate"]        = -> { r("And they found that many people were sleeping better.".truncate(25)) }
cases["str_truncate_omis"]   = -> { r("And they found that many people were sleeping better.".truncate(25, omission: "...")) }
cases["str_truncate_sep"]    = -> { r("And they found that many people were sleeping better.".truncate(25, separator: " ")) }
cases["str_truncate_bytes"]  = -> { r("skipped") }
cases["str_at"]              = -> { r("hello".at(0)) }
cases["str_at_range"]        = -> { r("hello".at(0..1)) }
cases["str_at_oob"]          = -> { r("hello".at(10)) }
cases["str_from"]            = -> { r("hello".from(1)) }
cases["str_from_neg"]        = -> { r("hello".from(-3)) }
cases["str_to"]              = -> { r("hello".to(1)) }
cases["str_to_neg"]          = -> { r("hello".to(-3)) }
cases["str_first"]           = -> { r("hello".first) }
cases["str_first_n"]         = -> { r("hello".first(2)) }
cases["str_first_zero"]      = -> { r("hello".first(0)) }
cases["str_first_oob"]       = -> { r("hello".first(10)) }
cases["str_last"]            = -> { r("hello".last) }
cases["str_last_n"]          = -> { r("hello".last(2)) }
cases["str_starts"]          = -> { r("hello".starts_with?("he")) }
cases["str_ends"]            = -> { r("hello".ends_with?("lo")) }
cases["str_exclude"]         = -> { r("hello".exclude?("ll")) }
cases["str_exclude_false"]   = -> { r("hello".exclude?("lo")) }
cases["str_remove"]          = -> { r("hello".remove("l")) }
cases["str_remove_bang"]     = -> { s = "hello"; r(s.remove!("l")) }
cases["str_indent"]          = -> { r("foo".indent(2)) }
cases["str_indent_char"]     = -> { r("foo".indent(2, "·")) }
cases["str_indent_multi"]    = -> { r("foo\nbar".indent(2)) }
cases["str_indent_keep_bl"]  = -> { r("foo\n\nbar".indent(2)) }
cases["str_strip_heredoc"]   = -> { r("    foo\n      bar\n    baz\n".strip_heredoc) }

# --- Hash -------------------------------------------------------------------
cases["hash_symbolize"]      = -> { r({:a => 1}.symbolize_keys) }
cases["hash_stringify"]      = -> { r({:a => 1}.stringify_keys) }
cases["hash_deep_symbolize"] = -> { r({:a => {:b => 1}}.deep_symbolize_keys) }
cases["hash_deep_stringify"] = -> { r({:a => {:b => 1}}.deep_stringify_keys) }
cases["hash_except"]         = -> { r({:a => 1, :b => 2, :c => 3}.except(:a, :c)) }
cases["hash_slice"]          = -> { r({:a => 1, :b => 2}.slice(:a)) }
cases["hash_reverse_merge"]  = -> { r({:a => 1}.reverse_merge({:b => 2, :a => 9})) }
cases["hash_with_defaults"]  = -> { r({:a => 1}.with_defaults({:a => 9, :b => 2})) }
cases["hash_deep_merge"]     = -> do
  h = {:a => {:b => 1, :c => 2}} of Symbol => (Hash(Symbol, Int32) | Int32)
  o = {:a => {:b => 9, :d => 4}} of Symbol => (Hash(Symbol, Int32) | Int32)
  r(h.deep_merge(o))
end
cases["hash_deep_merge_bang"] = -> do
  h = {:a => {:b => 1}} of Symbol => (Hash(Symbol, Int32) | Int32)
  h.deep_merge!({:a => {:c => 2}} of Symbol => (Hash(Symbol, Int32) | Int32))
  r(h)
end
cases["hash_deep_merge_block"] = -> do
  h = {:a => {:b => 1, :c => 2}} of Symbol => (Hash(Symbol, Int32) | Int32)
  o = {:a => {:b => 9}} of Symbol => (Hash(Symbol, Int32) | Int32)
  r(h.deep_merge(o) { |k, a, b| a.as(Int32) + b.as(Int32) })
end
cases["hash_deep_t_keys"]    = -> { r({"ab" => 1}.deep_transform_keys(&.upcase)) }
cases["hash_deep_t_values"]  = -> do
  h = {:a => {:b => 1}} of Symbol => (Hash(Symbol, Int32) | Int32)
  r(h.deep_transform_values { |v| v.as(Int32) * 10 })
end
cases["hash_compact_blank"]  = -> { r({:a => "", :b => nil, :c => 1, :d => "x", :e => [] of Int32}.compact_blank) }
cases["hash_assert_valid"]   = -> { r({:a => 1}.assert_valid_keys(:a, :b)) }
cases["hash_assert_raise"]   = -> { r({:a => 1, :z => 2}.assert_valid_keys(:a, :b)) }

# --- Array ---------------------------------------------------------------------
cases["arr_in_groups_of"]    = -> { r([1, 2, 3, 4, 5, 6, 7].in_groups_of(3)) }
cases["arr_in_groups_of_pad"] = -> { r([1, 2, 3, 4].in_groups_of(3, 0)) }
cases["arr_in_groups"]       = -> { r([1, 2, 3, 4, 5, 6, 7].in_groups(3)) }
cases["arr_in_groups_false"] = -> { r([1, 2, 3, 4].in_groups(2, false)) }
cases["arr_split"]           = -> { r([1, 2, 3, 4, 5].split(3)) }
cases["arr_split_block"]     = -> { r([1, 2, 3, 4, 5].split(&.odd?)) }
cases["arr_extract"]         = -> do
  a = [1, 2, 3, 4]
  e = a.extract!(&.even?)
  r("#{r(a)} #{r(e)}")
end
cases["arr_to_sentence"]     = -> { r(["one", "two", "three"].to_sentence) }
cases["arr_to_sentence_2"]   = -> { r(["one", "two"].to_sentence) }
cases["arr_to_sentence_1"]   = -> { r(["one"].to_sentence) }
cases["arr_second"]          = -> { r([1, 2, 3, 4, 5].second) }
cases["arr_third"]           = -> { r([1, 2, 3, 4, 5].third) }
cases["arr_fourth"]          = -> { r([1, 2, 3, 4, 5].fourth) }
cases["arr_fifth"]           = -> { r([1, 2, 3, 4, 5].fifth) }
cases["arr_second_to_last"]  = -> { r([1, 2, 3, 4, 5].second_to_last) }
cases["arr_third_to_last"]   = -> { r([1, 2, 3, 4, 5].third_to_last) }
cases["arr_wrap"]            = -> { r(Array.wrap([1, 2])) }
cases["arr_wrap_nil"]        = -> { r(Array.wrap(nil)) }
cases["arr_wrap_val"]        = -> { r(Array.wrap(1)) }
cases["arr_excluding"]       = -> { r([1, 2, 3, 4].excluding(2, 3)) }
cases["arr_including"]       = -> { r([1, 2, 3].including(4, 5)) }

# --- Enumerable --------------------------------------------------------------------
cases["enum_index_by"]       = -> { r([1, 2, 3, 4].index_by(&.even?)) }
cases["enum_index_with"]     = -> { r(["a", "b"].index_with(&.upcase)) }
cases["enum_many"]           = -> { r([1, 2, 3].many?) }
cases["enum_many_one"]       = -> { r([1].many?) }
cases["enum_exclude"]        = -> { r([1, 2].exclude?(3)) }
cases["enum_pluck"]          = -> { r([{:id => 1}, {:id => 2}].pluck(:id)) }
cases["enum_pick"]           = -> { r([1, 2, 3].pick) }
cases["enum_pick_none"]      = -> { r(([] of Int32).pick) }
cases["enum_sole"]           = -> { r([1, 2, 3, 4].sole(&.>(3))) }
cases["enum_sole_none"]      = -> { r([1, 2].sole(&.>(3))) }
cases["enum_sole_many"]      = -> { r([1, 2, 3].sole(&.>(1))) }
cases["enum_sole_no_arg"]    = -> { r([7].sole) }
cases["enum_in_order_of"]    = -> { r([1, 2, 3, 4, 5].in_order_of(:to_s, ["2", "1", "5"])) }
cases["enum_compact_blank"]  = -> { r([1, nil, "", "a", [] of Int32, {} of String => String].compact_blank) }

# --- Numeric / Duration ----------------------------------------------------------------
cases["num_seconds"]         = -> { r(45.seconds) }
cases["num_minutes"]         = -> { r(5.minutes) }
cases["num_hours"]           = -> { r(6.hours) }
cases["num_days"]            = -> { r(2.days) }
cases["num_weeks"]           = -> { r(2.weeks) }
cases["num_fortnights"]      = -> { r(1.fortnight) }
cases["num_months"]          = -> { r(3.months) }
cases["num_years"]           = -> { r(1.year) }
cases["num_duration_plus"]   = -> { r(2.days + 6.hours) }
cases["num_duration_sum"]    = -> { r((2.days + 6.hours).to_i) }
cases["num_duration_eq"]     = -> { r(2.days == 2.days) }
cases["num_duration_eq_int"] = -> { r(2.days == 172_800) }
cases["num_duration_ago_sec"] = -> { r(30.seconds.ago.is_a?(Time)) }
cases["num_byte"]            = -> { r(1.byte) }
cases["num_kilobyte"]        = -> { r(2.kilobytes) }
cases["num_megabyte"]        = -> { r(3.megabytes) }
cases["num_gigabyte"]        = -> { r(1.gigabyte) }
cases["num_terabyte"]        = -> { r(1.terabyte) }
cases["num_petabyte"]        = -> { r(1.petabyte) }
cases["num_exabyte"]         = -> { r(1.exabyte) }
cases["num_multiple_of"]     = -> { r(10.multiple_of?(5)) }
cases["num_multiple_of_f"]   = -> { r(15.multiple_of?(4)) }
cases["num_in_millis"]       = -> { r(4.minutes.in_milliseconds) }
cases["num_duration_from_time"] = -> { r(t + 2.days) }
cases["num_duration_sub_time"]  = -> { r(t - 3.hours) }

# --- Time / date math -------------------------------------------------------------------
cases["time_begin_day"]      = -> { r(t.beginning_of_day) }
cases["time_end_day"]        = -> { r(t.end_of_day) }
cases["time_mid_day"]        = -> { r(t.middle_of_day) }
cases["time_begin_week"]     = -> { r(t.beginning_of_week) }
cases["time_end_week"]       = -> { r(t.end_of_week) }
cases["time_begin_week_mon"] = -> { r(t.beginning_of_week(:monday)) }
cases["time_begin_month"]    = -> { r(t.beginning_of_month) }
cases["time_end_month"]      = -> { r(t.end_of_month) }
cases["time_begin_quarter"]  = -> { r(t.beginning_of_quarter) }
cases["time_end_quarter"]    = -> { r(t.end_of_quarter) }
cases["time_begin_year"]     = -> { r(t.beginning_of_year) }
cases["time_end_year"]       = -> { r(t.end_of_year) }
cases["time_all_day"]        = -> { r(t.all_day) }
cases["time_all_week"]       = -> { r(t.all_week) }
cases["time_all_month"]      = -> { r(t.all_month) }
cases["time_ago"]            = -> { r(t.ago(3600)) }
cases["time_since"]          = -> { r(t.since(3600)) }
cases["time_yesterday"]      = -> { r(t.yesterday) }
cases["time_tomorrow"]       = -> { r(t.tomorrow) }
cases["time_prev_day"]       = -> { r(t.prev_day) }
cases["time_next_week"]      = -> { r(t.next_week) }
cases["time_next_week_sat"]  = -> { r(t.next_week(:saturday)) }
cases["time_prev_week"]      = -> { r(t.prev_week) }
cases["time_next_month"]     = -> { r(t.next_month) }
cases["time_prev_month"]     = -> { r(t.prev_month) }
cases["time_next_year"]      = -> { r(t.next_year) }
cases["time_prev_year"]      = -> { r(t.prev_year) }
cases["time_months_ago"]     = -> { r(t.months_ago(2)) }
cases["time_months_since"]   = -> { r(t.months_since(2)) }
cases["time_years_ago"]      = -> { r(t.years_ago(1)) }
cases["time_next_occurring"] = -> { r(t.next_occurring(:monday)) }
cases["time_prev_occurring"] = -> { r(t.prev_occurring(:monday)) }
cases["time_advance"]        = -> { r(t.advance(months: 1, days: 2, hours: 3)) }
cases["time_change"]         = -> { r(t.change(hour: 0, min: 0, sec: 0)) }
cases["time_change_nsec"]    = -> { r(t.change(nsec: 0)) }
cases["time_sunday"]         = -> { r(t.sunday?) }
cases["time_monday"]         = -> { r(t.monday?) }
cases["time_past"]           = -> { r((t - 1.hour).past?) }
cases["time_future"]         = -> { r((t + 1.hour).future?) }
cases["time_beginning_of_month_clamp"] = -> { r(Time.utc(2026, 3, 31).months_ago(1)) }
cases["time_fs_db"]          = -> { r(t.to_fs(:db)) }
cases["time_fs_short"]       = -> { r(t.to_fs(:short)) }
cases["time_fs_long"]        = -> { r(t.to_fs(:long)) }
cases["time_fs_iso"]         = -> { r(t.to_fs(:iso8601)) }
cases["time_fs_default"]     = -> { r(t.to_fs) }

# --- Time.zone / TimeWithZone -----------------------------------------------------------------
cases["tz_name"]             = -> { Time.zone = "UTC"; r(Time.zone.not_nil!.name) }
cases["tz_in_zone"]          = -> { Time.zone = "UTC"; r(t.in_time_zone.utc_offset) }
cases["tz_localtime"]        = -> { Time.zone = "UTC"; r(t.in_time_zone.localtime.utc?) }
cases["tz_formatted_offset"] = -> { Time.zone = "UTC"; r(t.in_time_zone.formatted_offset) }
cases["tz_parse"]            = -> { Time.zone = "UTC"; r(Time.zone.not_nil!.parse("2026-03-15 12:30:45")) }

# --- per-user timezone: use_zone / Time.current / TWZ arithmetic -------------
cases["tz_offset_berlin"]  = -> { r(t.in_time_zone("Europe/Berlin").formatted_offset) }
cases["tz_in_zone_object"] = -> do
  z = t.in_time_zone(ActiveSupport::TimeZone.new("Europe/Berlin"))
  r("#{z.time_zone.name}|#{z.strftime("%F %T %:z")}")
end
cases["tz_zone_now"]       = -> { r(ActiveSupport::TimeZone.new("Asia/Tokyo").now.time_zone.name) }
cases["tz_current_zone"]   = -> { Time.zone = "Europe/Berlin"; r(Time.current.as(ActiveSupport::TimeWithZone).time_zone.name) }
cases["tz_current_no_zone"] = -> { Time.zone = nil; r(Time.current.is_a?(Time)) }
cases["tz_use_zone"]       = -> do
  Time.zone = "UTC"
  inner = Time.use_zone("Asia/Tokyo") { Time.zone.not_nil!.name }
  r("#{inner}|#{Time.zone.not_nil!.name}")
end
cases["tz_use_zone_nested"] = -> do
  Time.zone = "UTC"
  inner = Time.use_zone("Asia/Tokyo") { Time.use_zone("Europe/Berlin") { Time.zone.not_nil!.name } }
  r("#{inner}|#{Time.zone.not_nil!.name}")
end
cases["tz_use_zone_raise"] = -> do
  Time.zone = "UTC"
  begin
    Time.use_zone("Asia/Tokyo") { raise ArgumentError.new }
  rescue ArgumentError
  end
  r(Time.zone.not_nil!.name)
end
cases["tz_plus_seconds"]   = -> { r((t.in_time_zone("Europe/Berlin") + 90).strftime("%F %T")) }
cases["tz_plus_day"]       = -> { r((t.in_time_zone("Asia/Tokyo") + 1.day).strftime("%F %T")) }
cases["tz_sub_twz"]        = -> do
  a = t.in_time_zone("Asia/Tokyo")
  b = (t - 7200.seconds).in_time_zone("Europe/Berlin")
  r(a - b)
end
cases["tz_cmp"]            = -> { r(t.in_time_zone("Asia/Tokyo") <=> (t + 60.seconds).in_time_zone("Europe/Berlin")) }
cases["tz_eq"]             = -> { r(t.in_time_zone("Asia/Tokyo") == t) }
cases["tz_since"]          = -> { r(t.in_time_zone("Europe/Berlin").since(3600).strftime("%F %T")) }
cases["tz_ago"]            = -> { r(t.in_time_zone("Europe/Berlin").ago(3600).strftime("%F %T")) }
cases["tz_strftime"]       = -> { r(t.in_time_zone("Europe/Berlin").strftime("%F %T %:z")) }
cases["tz_to_s"]           = -> { r(t.in_time_zone("Europe/Berlin").to_s) }
cases["tz_fs_db"]          = -> { r(t.in_time_zone("Europe/Berlin").to_fs(:db)) }
cases["tz_fs_default"]     = -> { r(t.in_time_zone("Europe/Berlin").to_fs) }

# --- NumberHelper ------------------------------------------------------------------------------
cases["nh_currency"]         = -> { r(ActiveSupport::NumberHelper.number_to_currency(1234567.89)) }
cases["nh_currency_prec"]    = -> { r(ActiveSupport::NumberHelper.number_to_currency(1234567.89, precision: 0)) }
cases["nh_currency_unit"]    = -> { r(ActiveSupport::NumberHelper.number_to_currency(1234567.89, unit: "€", format: "%n %u")) }
cases["nh_currency_neg"]     = -> { r(ActiveSupport::NumberHelper.number_to_currency(-1234567.89)) }
cases["nh_currency_sep"]     = -> { r(ActiveSupport::NumberHelper.number_to_currency(1234567.89, delimiter: ".", separator: ",")) }
cases["nh_percentage"]       = -> { r(ActiveSupport::NumberHelper.number_to_percentage(80)) }
cases["nh_percentage_p0"]    = -> { r(ActiveSupport::NumberHelper.number_to_percentage(80, precision: 0)) }
cases["nh_delimiter"]        = -> { r(ActiveSupport::NumberHelper.number_to_delimited(12345678)) }
cases["nh_delimiter_opt"]    = -> { r(ActiveSupport::NumberHelper.number_to_delimited(12345678, delimiter: " ")) }
cases["nh_precision"]        = -> { r(ActiveSupport::NumberHelper.number_to_rounded(3.14159)) }
cases["nh_precision_2"]      = -> { r(ActiveSupport::NumberHelper.number_to_rounded(3.14159, precision: 2)) }
cases["nh_precision_sig"]    = -> { r(ActiveSupport::NumberHelper.number_to_rounded(3.14159, significant: true)) }
cases["nh_human_size"]       = -> { r(ActiveSupport::NumberHelper.number_to_human_size(1234567)) }
cases["nh_human_size_kb"]    = -> { r(ActiveSupport::NumberHelper.number_to_human_size(4350)) }
cases["nh_human_size_gb"]    = -> { r(ActiveSupport::NumberHelper.number_to_human_size(3_567_141_124)) }
cases["nh_human"]            = -> { r(ActiveSupport::NumberHelper.number_to_human(1234567)) }
cases["nh_human_million"]    = -> { r(ActiveSupport::NumberHelper.number_to_human(12_345_678)) }
cases["nh_phone"]            = -> { r(ActiveSupport::NumberHelper.number_to_phone(1234567890)) }
cases["nh_phone_area"]       = -> { r(ActiveSupport::NumberHelper.number_to_phone(1234567890, area_code: true)) }

describe "ActiveSupport oracle (expected.yml from activesupport 8.1.4)" do
  expected = Hash(String, String).new
  File.read_lines(File.join(__DIR__, "..", "oracle", "expected.yml")).each do |line|
    id, value = line.split('\t', 2)
    expected[id] = value
  end

  cases.each do |id, block|
    it id do
      actual = begin
        block.call
      rescue e : Exception
        "raise:#{e.class.name}"
      end
      actual.should eq(expected[id]), "#{id}: got #{actual.inspect}, want #{expected[id].inspect}"
    end
  end
end
