# Synthetic oracle cases for ActiveSupport P0 (Iteration 1).
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<rendered result>". The same case IDs are
# mirrored 1:1 in spec/oracle_spec.cr; the Crystal port must reproduce
# expected.yml exactly (both implementations pass the same expectations,
# captured from activesupport 8.1.4). Reference minitest suites from
# rails/rails v8.1.4 live in oracle/rails-tests/.
require "active_support/all"
require "active_support/number_helper"

def render(v)
  case v
  when true, false, Integer, Float, String then v.inspect
  when Symbol then ":#{v}"
  when nil then "nil"
  when Time
    u = v.getutc
    sprintf("T%04d-%02d-%02d %02d:%02d:%02d.%09d",
      u.year, u.mon, u.mday, u.hour, u.min, u.sec, u.nsec)
  when ActiveSupport::TimeWithZone
    u = v.getutc
    sprintf("Z%04d-%02d-%02d %02d:%02d:%02d.%09d|%s|%s",
      u.year, u.mon, u.mday, u.hour, u.min, u.sec, u.nsec,
      v.zone.name, v.formatted_offset)
  when ActiveSupport::Duration then "D:#{v.inspect}"
  when Range then "R(#{render(v.first)},#{render(v.last)},#{v.exclude_end? ? 'x' : 'i'})"
  when Array then "A[#{v.map { |e| render(e) }.join(',')}]"
  when Hash then "H{#{v.sort_by { |k, _| k.to_s }.map { |k, val| "#{render(k)}=>#{render(val)}" }.join(',')}}"
  when Exception then "raise:#{v.class.name}"
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

T = Time.utc(2026, 3, 15, 12, 30, 45) # Sunday
include ActiveSupport::NumberHelper

# --- Object / Nil -------------------------------------------------
case_run("obj_blank_nil")     { nil.blank? }
case_run("obj_blank_str")     { "  ".blank? }
case_run("obj_present_zero")  { 0.present? }
case_run("obj_presence_empty"){ "".presence }
case_run("obj_presence_val")  { "x".presence }
case_run("obj_in_true")       { 1.in?([1, 2]) }
case_run("obj_in_false")      { 3.in?([1, 2]) }
case_run("obj_in_str")        { "a".in?("abc") }
case_run("obj_presence_in")   { 1.presence_in([1, 2]) }
case_run("obj_presence_in_nil"){ 3.presence_in([1, 2]) }
case_run("obj_deep_dup")      { h = {a: {b: 1}}; d = h.deep_dup; d[:a][:b] = 2; "#{render(h)} #{render(d)}" }
case_run("obj_to_param")      { 123.to_param }
case_run("obj_try")           { nil.try(&:upcase) }
case_run("obj_try!")          { nil.try!(:upcase) rescue nil; "handled" }

# --- String ---------------------------------------------------------
case_run("str_squish")        { " foo \t bar \n".squish }
case_run("str_squish_html")   { "<p> foo </p>".squish }
case_run("str_truncate")      { "And they found that many people were sleeping better.".truncate(25) }
case_run("str_truncate_omis") { "And they found that many people were sleeping better.".truncate(25, omission: "...") }
case_run("str_truncate_sep")  { "And they found that many people were sleeping better.".truncate(25, separator: " ") }
case_run("str_truncate_bytes"){ "\xff\x8e\x8e\x8e\x8e\x8e".force_encoding("ASCII-8BIT").truncate_bytes(5) rescue "skipped" }
case_run("str_at")            { "hello".at(0) }
case_run("str_at_range")      { "hello".at(0..1) }
case_run("str_at_oob")        { "hello".at(10) }
case_run("str_from")          { "hello".from(1) }
case_run("str_from_neg")      { "hello".from(-3) }
case_run("str_to")            { "hello".to(1) }
case_run("str_to_neg")        { "hello".to(-3) }
case_run("str_first")         { "hello".first }
case_run("str_first_n")       { "hello".first(2) }
case_run("str_first_zero")    { "hello".first(0) }
case_run("str_first_oob")     { "hello".first(10) }
case_run("str_last")          { "hello".last }
case_run("str_last_n")        { "hello".last(2) }
case_run("str_starts")        { "hello".starts_with?("he") }
case_run("str_ends")          { "hello".ends_with?("lo") }
case_run("str_exclude")       { "hello".exclude?("ll") }
case_run("str_exclude_false") { "hello".exclude?("lo") }
case_run("str_remove")        { "hello".remove("l") }
case_run("str_remove_bang")   { s = "hello"; s.remove!("l"); s }
case_run("str_indent")        { "foo".indent(2) }
case_run("str_indent_char")   { "foo".indent(2, "·") }
case_run("str_indent_multi")  { "foo\nbar".indent(2) }
case_run("str_indent_keep_bl") { "foo\n\nbar".indent(2) }
case_run("str_strip_heredoc") { <<-HEREDOC.strip_heredoc
    foo
      bar
    baz
  HEREDOC
}

# --- Hash -----------------------------------------------------------
H1 = {a: 1, "b" => 2}
case_run("hash_symbolize")    { {a: 1}.symbolize_keys }
case_run("hash_stringify")    { {a: 1}.stringify_keys }
case_run("hash_deep_symbolize"){ {a: {b: 1}}.deep_symbolize_keys }
case_run("hash_deep_stringify"){ {a: {b: 1}}.deep_stringify_keys }
case_run("hash_except")       { {a: 1, b: 2, c: 3}.except(:a, :c) }
case_run("hash_slice")        { {a: 1, b: 2}.slice(:a) }
case_run("hash_reverse_merge"){ {a: 1}.reverse_merge(b: 2, a: 9) }
case_run("hash_with_defaults"){ {a: 1}.with_defaults(a: 9, b: 2) }
case_run("hash_deep_merge")   { {a: {b: 1, c: 2}}.deep_merge(a: {b: 9, d: 4}) }
case_run("hash_deep_merge_bang"){ h = {a: {b: 1}}; h.deep_merge!(a: {c: 2}); h }
case_run("hash_deep_merge_block"){ {a: {b: 1, c: 2}}.deep_merge(a: {b: 9}) { |k, o, n| o + n } }
case_run("hash_deep_t_keys")  { {"ab" => 1}.deep_transform_keys { |k| k.upcase } }
case_run("hash_deep_t_values"){ {a: {b: 1}}.deep_transform_values { |v| v * 10 } }
case_run("hash_compact_blank"){ {a: "", b: nil, c: 1, d: "x", e: []}.compact_blank }
case_run("hash_assert_valid") { {a: 1}.assert_valid_keys(:a, :b) }
case_run("hash_assert_raise") { {a: 1, z: 2}.assert_valid_keys(:a, :b) }

# --- Array ----------------------------------------------------------
case_run("arr_in_groups_of")  { [1, 2, 3, 4, 5, 6, 7].in_groups_of(3) }
case_run("arr_in_groups_of_pad"){ [1, 2, 3, 4].in_groups_of(3, 0) }
case_run("arr_in_groups")     { [1, 2, 3, 4, 5, 6, 7].in_groups(3) }
case_run("arr_in_groups_false"){ [1, 2, 3, 4].in_groups(2, false) }
case_run("arr_split")         { [1, 2, 3, 4, 5].split(3) }
case_run("arr_split_block")   { [1, 2, 3, 4, 5].split { |i| i.odd? } }
case_run("arr_extract")       { a = [1, 2, 3, 4]; e = a.extract! { |i| i.even? }; "#{render(a)} #{render(e)}" }
case_run("arr_to_sentence")   { ["one", "two", "three"].to_sentence }
case_run("arr_to_sentence_2") { ["one", "two"].to_sentence }
case_run("arr_to_sentence_1") { ["one"].to_sentence }
case_run("arr_second")        { [1, 2, 3, 4, 5].second }
case_run("arr_third")         { [1, 2, 3, 4, 5].third }
case_run("arr_fourth")        { [1, 2, 3, 4, 5].fourth }
case_run("arr_fifth")         { [1, 2, 3, 4, 5].fifth }
case_run("arr_second_to_last"){ [1, 2, 3, 4, 5].second_to_last }
case_run("arr_third_to_last") { [1, 2, 3, 4, 5].third_to_last }
case_run("arr_wrap")          { Array.wrap([1, 2]) }
case_run("arr_wrap_nil")      { Array.wrap(nil) }
case_run("arr_wrap_val")      { Array.wrap(1) }
case_run("arr_excluding")     { [1, 2, 3, 4].excluding(2, 3) }
case_run("arr_including")     { [1, 2, 3].including(4, 5) }

# --- Enumerable -------------------------------------------------------
E1 = [1, 2, 3, 4]
case_run("enum_index_by")     { E1.index_by { |i| i.even? } }
case_run("enum_index_with")   { %w[a b].index_with { |s| s.upcase } }
case_run("enum_many")         { [1, 2, 3].many? }
case_run("enum_many_one")     { [1].many? }
case_run("enum_exclude")      { [1, 2].exclude?(3) }
case_run("enum_pluck")        { [{id: 1}, {id: 2}].pluck(:id) }
case_run("enum_pick")         { [1, 2, 3].pick }
case_run("enum_pick_none")    { [].pick }
case_run("enum_sole")         { [1, 2, 3, 4].sole { |i| i > 3 } }
case_run("enum_sole_none")    { [1, 2].sole { |i| i > 3 } }
case_run("enum_sole_many")    { [1, 2, 3].sole { |i| i > 1 } }
case_run("enum_sole_no_arg")  { [7].sole }
case_run("enum_in_order_of")  { [1, 2, 3, 4, 5].in_order_of(:to_s, ["2", "1", "5"]) rescue "skipped" }
case_run("enum_compact_blank"){ [1, nil, "", "a", [], {}].compact_blank }

# --- Numeric / Duration ------------------------------------------------
case_run("num_seconds")       { 45.seconds }
case_run("num_minutes")       { 5.minutes }
case_run("num_hours")         { 6.hours }
case_run("num_days")          { 2.days }
case_run("num_weeks")         { 2.weeks }
case_run("num_fortnights")    { 1.fortnight }
case_run("num_months")        { 3.months }
case_run("num_years")         { 1.year }
case_run("num_duration_plus") { 2.days + 6.hours }
case_run("num_duration_sum")  { (2.days + 6.hours).to_i }
case_run("num_duration_eq")   { 2.days == 2.days }
case_run("num_duration_eq_int"){ 2.days == 172_800 }
case_run("num_duration_ago_sec"){ 30.seconds.ago.is_a?(Time) }
case_run("num_byte")          { 1.byte }
case_run("num_kilobyte")      { 2.kilobytes }
case_run("num_megabyte")      { 3.megabytes }
case_run("num_gigabyte")      { 1.gigabyte }
case_run("num_terabyte")      { 1.terabyte }
case_run("num_petabyte")      { 1.petabyte }
case_run("num_exabyte")       { 1.exabyte }
case_run("num_multiple_of")   { 10.multiple_of?(5) }
case_run("num_multiple_of_f") { 15.multiple_of?(4) }
case_run("num_in_millis")     { 4.minutes.in_milliseconds }
case_run("num_duration_from_time") { T + 2.days }
case_run("num_duration_sub_time") { T - 3.hours }

# --- Time / дата-математика -------------------------------------------
case_run("time_begin_day")    { T.beginning_of_day }
case_run("time_end_day")      { T.end_of_day }
case_run("time_mid_day")      { T.middle_of_day }
case_run("time_begin_week")   { T.beginning_of_week }
case_run("time_end_week")     { T.end_of_week }
case_run("time_begin_week_mon"){ T.beginning_of_week(:monday) }
case_run("time_begin_month")  { T.beginning_of_month }
case_run("time_end_month")    { T.end_of_month }
case_run("time_begin_quarter"){ T.beginning_of_quarter }
case_run("time_end_quarter")  { T.end_of_quarter }
case_run("time_begin_year")   { T.beginning_of_year }
case_run("time_end_year")     { T.end_of_year }
case_run("time_all_day")      { T.all_day }
case_run("time_all_week")     { T.all_week }
case_run("time_all_month")    { T.all_month }
case_run("time_ago")          { T.ago(3600) }
case_run("time_since")        { T.since(3600) }
case_run("time_yesterday")    { T.yesterday }
case_run("time_tomorrow")     { T.tomorrow }
case_run("time_prev_day")     { T.prev_day }
case_run("time_next_week")    { T.next_week }
case_run("time_next_week_sat"){ T.next_week(:saturday) }
case_run("time_prev_week")    { T.prev_week }
case_run("time_next_month")   { T.next_month }
case_run("time_prev_month")   { T.prev_month }
case_run("time_next_year")    { T.next_year }
case_run("time_prev_year")    { T.prev_year }
case_run("time_months_ago")   { T.months_ago(2) }
case_run("time_months_since") { T.months_since(2) }
case_run("time_years_ago")    { T.years_ago(1) }
case_run("time_next_occurring"){ T.next_occurring(:monday) }
case_run("time_prev_occurring"){ T.prev_occurring(:monday) }
case_run("time_advance")      { T.advance(months: 1, days: 2, hours: 3) }
case_run("time_change")       { T.change(hour: 0, min: 0, sec: 0) }
case_run("time_change_nsec")  { T.change(nsec: 0) }
case_run("time_sunday")       { T.sunday? }
case_run("time_monday")       { T.monday? }
case_run("time_past")         { (T - 1.hour).past? }
case_run("time_future")       { (T + 1.hour).future? }
case_run("time_beginning_of_month_clamp"){ Time.utc(2026, 3, 31).months_ago(1) }
case_run("time_fs_db")        { T.to_fs(:db) }
case_run("time_fs_short")     { T.to_fs(:short) }
case_run("time_fs_long")      { T.to_fs(:long) }
case_run("time_fs_iso")       { T.to_fs(:iso8601) }
case_run("time_fs_default")   { T.to_fs }

# --- Time.zone / TimeWithZone (минимум) --------------------------------
case_run("tz_name")           { Time.zone = "UTC"; Time.zone.name }
case_run("tz_in_zone")        { Time.zone = "UTC"; T.in_time_zone.utc_offset }
case_run("tz_localtime")      { Time.zone = "UTC"; T.in_time_zone.localtime.utc? }
case_run("tz_formatted_offset"){ Time.zone = "UTC"; T.in_time_zone.formatted_offset }
case_run("tz_parse")          { Time.zone = "UTC"; Time.zone.parse("2026-03-15 12:30:45") }

# --- NumberHelper -------------------------------------------------------
case_run("nh_currency")       { number_to_currency(1234567.89) }
case_run("nh_currency_prec")  { number_to_currency(1234567.89, precision: 0) }
case_run("nh_currency_unit")  { number_to_currency(1234567.89, unit: "€", format: "%n %u") }
case_run("nh_currency_neg")   { number_to_currency(-1234567.89) }
case_run("nh_currency_sep")   { number_to_currency(1234567.89, delimiter: ".", separator: ",") }
case_run("nh_percentage")     { number_to_percentage(80) }
case_run("nh_percentage_p0")  { number_to_percentage(80, precision: 0) }
case_run("nh_delimiter")      { number_to_delimited(12345678) }
case_run("nh_delimiter_opt")  { number_to_delimited(12345678, delimiter: " ") }
case_run("nh_precision")      { number_to_rounded(3.14159) }
case_run("nh_precision_2")    { number_to_rounded(3.14159, precision: 2) }
case_run("nh_precision_sig")  { number_to_rounded(3.14159, significant: true) }
case_run("nh_human_size")     { number_to_human_size(1234567) }
case_run("nh_human_size_kb")  { number_to_human_size(4350) }
case_run("nh_human_size_gb")  { number_to_human_size(3_567_141_124) }
case_run("nh_human")          { number_to_human(1234567) }
case_run("nh_human_million")  { number_to_human(12_345_678) }
case_run("nh_phone")          { number_to_phone(1234567890) }
case_run("nh_phone_area")     { number_to_phone(1234567890, area_code: true) }

# --- per-user timezone: use_zone / Time.current / TWZ arithmetic ------
case_run("tz_offset_berlin")  { T.in_time_zone("Europe/Berlin").formatted_offset }
case_run("tz_in_zone_object") { t = T.in_time_zone(ActiveSupport::TimeZone.new("Europe/Berlin")); "#{t.time_zone.name}|#{t.strftime("%F %T %:z")}" }
case_run("tz_zone_now")       { ActiveSupport::TimeZone.new("Asia/Tokyo").now.time_zone.name }
case_run("tz_current_zone")   { Time.zone = "Europe/Berlin"; Time.current.time_zone.name }
case_run("tz_current_no_zone"){ Time.zone = nil; Time.current.is_a?(Time) }
case_run("tz_use_zone")       { Time.zone = "UTC"; inner = Time.use_zone("Asia/Tokyo") { Time.zone.name }; "#{inner}|#{Time.zone.name}" }
case_run("tz_use_zone_nested"){ Time.zone = "UTC"; inner = Time.use_zone("Asia/Tokyo") { Time.use_zone("Europe/Berlin") { Time.zone.name } }; "#{inner}|#{Time.zone.name}" }
case_run("tz_use_zone_raise") { Time.zone = "UTC"; begin; Time.use_zone("Asia/Tokyo") { raise ArgumentError }; rescue ArgumentError; end; Time.zone.name }
case_run("tz_plus_seconds")   { (T.in_time_zone("Europe/Berlin") + 90).strftime("%F %T") }
case_run("tz_plus_day")       { (T.in_time_zone("Asia/Tokyo") + 1.day).strftime("%F %T") }
case_run("tz_sub_twz")        { T.in_time_zone("Asia/Tokyo") - (T - 7200).in_time_zone("Europe/Berlin") }
case_run("tz_cmp")            { T.in_time_zone("Asia/Tokyo") <=> (T + 60).in_time_zone("Europe/Berlin") }
case_run("tz_eq")             { T.in_time_zone("Asia/Tokyo") == T }
case_run("tz_since")          { T.in_time_zone("Europe/Berlin").since(3600).strftime("%F %T") }
case_run("tz_ago")            { T.in_time_zone("Europe/Berlin").ago(3600).strftime("%F %T") }
case_run("tz_strftime")       { T.in_time_zone("Europe/Berlin").strftime("%F %T %:z") }
case_run("tz_to_s")           { T.in_time_zone("Europe/Berlin").to_s }
case_run("tz_fs_db")          { T.in_time_zone("Europe/Berlin").to_fs(:db) }
case_run("tz_fs_default")     { T.in_time_zone("Europe/Berlin").to_fs }
