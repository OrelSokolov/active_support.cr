# ActiveSupport core_ext P0: Object/Nil/String/Hash/Array/Enumerable/
# Numeric — port of Rails 8 core_ext, verified against oracle/expected.yml
# (synthetic cases captured from activesupport 8.1.4) plus the original
# minitest suites vendored in oracle/rails-tests/.

# Ruby exception names absent from the Crystal stdlib.
class TypeError < Exception
end

module ActiveSupport
  # Recursive "any scalar or nested container" type — Crystal cannot
  # express recursive Hash types, and Object is not a valid generic
  # argument. Used as value type for deep key conversion results.
  alias Any = Nil | Bool | Int32 | Int64 | Float64 | String | Symbol |
              Array(Any) | Hash(String, Any) | Hash(Symbol, Any)
end

class Object
  def blank? : Bool
    false
  end

  def present? : Bool
    !blank?
  end

  def presence : self?
    present? ? self : nil
  end

  # nil.try stays nil, like in Rails.
  def try(&)
    yield self
  end

  # try! raises on nil receivers instead of returning nil.
  def try!( &)
    yield self
  end

  def in?(collection : Enumerable) : Bool
    collection.includes?(self)
  end

  def in?(collection : String) : Bool
    collection.includes?(self.as(String))
  end

  def presence_in(collection : Enumerable) : self?
    collection.includes?(self) ? self : nil
  end

  def deep_dup
    dup
  end

  def to_param : String
    to_s
  end
end

struct Nil
  def blank? : Bool
    true
  end

  def present? : Bool
    false
  end

  # Block is never called (matching Rails nil.try).
  def try(&) : Nil
    nil
  end

  def try!(&) : Nil
    raise Exception.new("NoMethodError: undefined method for nil")
  end
end

class String
  def blank? : Bool
    strip.empty?
  end

  # --- filters ---------------------------------------------------------

  def squish : String
    strip.gsub(/\s+/, " ")
  end

  def truncate(length : Int, omission : String = "...", separator : String? = nil) : String
    return self if length >= size
    limit = length - omission.size
    if separator
      stop = nil
      idx = index(separator)
      while idx && idx <= limit
        stop = idx
        nxt = index(separator, idx + separator.size)
        break unless nxt && nxt <= limit
        idx = nxt
      end
      return self[0, stop] + omission if stop && stop > 0
    end
    self[0, {limit, 0}.max] + omission
  end

  def truncate_bytes(length : Int, omission : String = "...") : String
    return self if bytesize <= length
    stop = {length - omission.bytesize, 0}.max
    self.byte_slice(0, stop) + omission
  end

  # --- access ----------------------------------------------------------

  def at(position : Int) : String?
    if position < 0
      return nil if -position > size
      self[position..]
    else
      return nil if position >= size
      self[position, 1]
    end
  end

  def at(position : Range) : String?
    self[position]?
  end

  def from(position : Int) : String?
    return nil if position >= size || position <= -size
    position < 0 ? self[position..] : self[position..]
  end

  def to(position : Int) : String?
    return nil if position >= size || position <= -size
    self[0..position]
  end

  def first : String
    self[0, 1]
  end

  def first(max : Int) : String
    raise ArgumentError.new("negative string size") if max < 0
    max == 0 ? "" : self[0, {max, size}.min]
  end

  def last : String
    self[-1, 1]
  end

  def last(max : Int) : String
    raise ArgumentError.new("negative string size") if max < 0
    max == 0 ? "" : self[{size - {max, size}.min, 0}.max..]
  end

  def starts_with?(*prefixes : String) : Bool
    prefixes.any? { |p| starts_with?(p) }
  end

  def ends_with?(*suffixes : String) : Bool
    suffixes.any? { |s| ends_with?(s) }
  end

  def exclude?(obj : String) : Bool
    !includes?(obj)
  end

  def remove(pattern : String) : String
    gsub(pattern, "")
  end

  def remove(pattern : Regex) : String
    gsub(pattern, "")
  end

  # Strings are immutable in Crystal: `remove!` returns the new string
  # rather than mutating in place (documented API deviation).
  def remove!(pattern : String | Regex) : String
    remove(pattern)
  end

  def indent(amount : Int, pad : String = " ", indent_empty_lines : Bool = false) : String
    return self if amount == 0
    padding = pad * amount.abs
    lines = split('\n', remove_empty: false)
    lines.map! do |line|
      if line.empty? && !indent_empty_lines
        line
      elsif amount < 0
        line.sub(/^#{padding}/, "")
      else
        padding + line
      end
    end
    lines.join('\n')
  end

  def strip_heredoc : String
    indents = [] of Int32
    each_line do |line|
      next if line.strip.empty?
      indents << (line.size - line.lstrip.size)
    end
    min = indents.min?
    return self if min.nil? || min == 0
    lines = split('\n', remove_empty: false)
    lines.map { |line| line.sub(/^[ \t]{#{min}}/, "") }.join('\n')
  end
end

module Indexable
  def blank? : Bool
    empty?
  end
end

class Hash
  def blank? : Bool
    empty?
  end

  def symbolize_keys : Hash(Symbol, V)
    out = {} of Symbol => V
    each { |k, v| out[k] = v }
    out
  end

  def stringify_keys : Hash(String, V)
    out = {} of String => V
    each { |k, v| out[k.to_s] = v }
    out
  end

  def deep_symbolize_keys : Hash(Symbol, ActiveSupport::Any)
    Hash.symbolize_r(self)
  end

  def deep_stringify_keys : Hash(String, ActiveSupport::Any)
    Hash.stringify_r(self)
  end

  def deep_transform_keys(&block : K -> K) : Hash(K, V)
    out = {} of K => V
    each do |k, v|
      out[block.call(k)] = v.is_a?(Hash) ? sub_hash(v).deep_transform_keys(&block).as?(V) || v : v
    end
    out
  end

  def deep_transform_values(&block : V -> V) : Hash(K, V)
    Hash.transform_values_r(self, block)
  end

  def except(*keys) : Hash(K, V)
    reject { |k, _| keys.includes?(k) }
  end

  def slice(*keys) : Hash(K, V)
    out = {} of K => V
    each { |k, v| out[k] = v if keys.includes?(k) }
    out
  end

  def reverse_merge(other : Hash(K, V)) : Hash(K, V)
    other.merge(self)
  end

  def reverse_merge!(other : Hash(K, V)) : self
    merge!(other) { |_k, _ours, theirs| theirs }
    self
  end

  def with_defaults(other : Hash(K, V)) : Hash(K, V)
    reverse_merge(other)
  end

  def deep_merge(other : Hash(K, V)) : Hash(K, V)
    deep_merge(other) { |_k, _ours, theirs| theirs }
  end

  def deep_merge(other : Hash(K, V), &block : K, V, V -> V) : Hash(K, V)
    Hash.merge_r(self, other, block)
  end

  def deep_merge!(other : Hash(K, V)) : self
    merged = deep_merge(other)
    clear
    merge!(merged)
    self
  end

  # Recursive deep-merge worker: block type stays fixed at the OUTERMOST
  # instantiation while inner hashes merge at their own K/V (inner values
  # are members of the outer V union, hence the casts).
  def self.merge_r(a, b, block : Proc(KB, VB, VB, VB)) forall KB, VB
    out = a.dup
    b.each do |k, theirs|
      ours = out[k]?
      if ours.is_a?(Hash) && theirs.is_a?(Hash)
        out[k] = merge_r(ours, theirs, block)
      elsif ours
        out[k] = block.call(k.as(KB), ours.as(VB), theirs.as(VB)).as(typeof(ours))
      else
        out[k] = theirs
      end
    end
    out
  end

  def compact_blank : Hash(K, V)
    reject { |_, v| v.blank? }
  end

  def assert_valid_keys(*valid_keys) : self
    each_key do |key|
      unless valid_keys.includes?(key)
        raise ArgumentError.new("Unknown key: #{key.inspect}. Valid keys: #{valid_keys.map(&.inspect).join(", ")}.")
      end
    end
    self
  end

  def deep_dup : Hash(K, V)
    out = {} of K => V
    each do |k, v|
      out[k] = v.is_a?(Hash) ? sub_hash(v).deep_dup.as?(V) || v : v.deep_dup.as?(V) || v
    end
    out
  end

  # Recursive value transformer (same pattern as merge_r).
  def self.transform_values_r(h, block : Proc(VB, VB)) forall VB
    out = h.dup
    h.each do |k, v|
      out[k] = v.is_a?(Hash) ? transform_values_r(v, block) : block.call(v.as(VB)).as(typeof(v))
    end
    out
  end

  # Recursive key-type converters (values widen to ActiveSupport::Any —
  # Crystal cannot express recursive hash types).
  def self.stringify_r(h) : Hash(String, ActiveSupport::Any)
    out = {} of String => ActiveSupport::Any
    h.each do |k, v|
      out[k.to_s] = v.is_a?(Hash) ? stringify_r(v).as(ActiveSupport::Any) : v.as(ActiveSupport::Any)
    end
    out
  end

  def self.symbolize_r(h) : Hash(Symbol, ActiveSupport::Any)
    out = {} of Symbol => ActiveSupport::Any
    h.each do |k, v|
      out[k.as(Symbol)] = v.is_a?(Hash) ? symbolize_r(v).as(ActiveSupport::Any) : v.as(ActiveSupport::Any)
    end
    out
  end

  private def sub_hash(v)
    v.as(Hash(typeof(v.keys.first), typeof(v.values.first)))
  end
end

class Array
  def blank? : Bool
    empty?
  end

  # --- grouping ----------------------------------------------------------

  def in_groups_of(number : Int, fill_with : Nil = nil) : Array(Array(T | Nil))
    raise ArgumentError.new("group size must be > 0") if number <= 0
    groups = [] of Array(T | Nil)
    each_slice(number) do |slice|
      groups << slice.map(&.as(T | Nil))
    end
    if groups.last? && groups.last.size < number
      (number - groups.last.size).times { groups.last << nil }
    end
    groups
  end

  def in_groups_of(number : Int, fill_with : V) : Array(Array(T | V)) forall V
    raise ArgumentError.new("group size must be > 0") if number <= 0
    groups = [] of Array(T | V)
    each_slice(number) do |slice|
      groups << slice.map(&.as(T | V))
    end
    if groups.last? && groups.last.size < number
      (number - groups.last.size).times { groups.last << fill_with }
    end
    groups
  end

  def in_groups(number : Int, fill_with : Nil | Bool = nil) : Array(Array(T | Nil))
    raise ArgumentError.new("group count must be > 0") if number <= 0
    division = size // number
    modulo = size.remainder(number)
    groups = [] of Array(T | Nil)
    start = 0
    number.times do |index|
      length = division + (modulo > 0 && modulo > index ? 1 : 0)
      padding = !fill_with && modulo > 0 && length <= division ? 1 : 0
      group = self[start, length]?.try(&.map(&.as(T | Nil))) || ([] of T | Nil)
      padding.times { group << nil }
      groups << group
      start += length
    end
    groups
  end

  def split(pattern : T2) : Array(Array(T)) forall T2
    split { |e| e == pattern }
  end

  def split(&block : T -> _) : Array(Array(T))
    result = [] of Array(T)
    current = [] of T
    each do |element|
      if block.call(element)
        result << current
        current = [] of T
      else
        current << element
      end
    end
    result << current
    result
  end

  def extract!(&block : T -> _) : Array(T)
    extracted = self.select(&block)
    reject!(&block)
    extracted
  end

  # --- sentence ----------------------------------------------------------

  def to_sentence(words_connector : String = ", ", two_words_connector : String = " and ",
                  last_word_connector : String = ", and ") : String
    case size
    when 0 then ""
    when 1 then self[0].to_s
    when 2 then "#{self[0]}#{two_words_connector}#{self[1]}"
    else
      "#{self[0...-1].map(&.to_s).join(words_connector)}#{last_word_connector}#{self.last}"
    end
  end

  # --- access ------------------------------------------------------------

  def second : T?
    self[1]?
  end

  def third : T?
    self[2]?
  end

  def fourth : T?
    self[3]?
  end

  def fifth : T?
    self[4]?
  end

  def second_to_last : T?
    self[-2]?
  end

  def third_to_last : T?
    self[-3]?
  end

  def excluding(*elements) : Array(T)
    reject { |e| elements.includes?(e) }
  end

  def including(*elements : T) : Array(T)
    self + elements.to_a
  end

  def self.wrap(object : U) : Array(U) forall U
    if object.nil?
      [] of U
    else
      [object]
    end
  end

  def self.wrap(object : Array(U)) : Array(U) forall U
    object.dup
  end

  def deep_dup : Array(T)
    map { |e| e.deep_dup.as(T) }
  end

  def to_param : String
    join("/")
  end
end

module Enumerable(T)
  # Object#blank? cooperation for compact_blank.
  def exclude?(object) : Bool
    !includes?(object)
  end

  def many?(&block : T -> _) : Bool
    seen = 0
    each do |element|
      next unless block.call(element)
      seen += 1
      return true if seen > 1
    end
    false
  end

  def many? : Bool
    seen = 0
    each do
      seen += 1
      return true if seen > 1
    end
    false
  end

  def index_by(&block : T -> K) : Hash(K, T) forall K
    out = {} of K => T
    each { |e| out[block.call(e)] = e }
    out
  end

  def index_with(&block : T -> V2) : Hash(T, V2) forall V2
    out = {} of T => V2
    each { |e| out[e] = block.call(e) }
    out
  end

  def compact_blank : Array(T)
    result = [] of T
    each { |e| result << e unless e.blank? }
    result
  end

  def in_order_of(property : Symbol, values : Enumerable(V2)) : Array(T) forall V2
    keyed = {} of String => Array(T)
    each do |element|
      key = case property
            when :to_s then element.to_s
            when :to_i then element.to_i.to_s
            else            raise ArgumentError.new("in_order_of: unsupported property #{property} (P0 supports :to_s/:to_i)")
            end
      (keyed[key] ||= [] of T) << element
    end
    result = [] of T
    values.each { |v| result.concat(keyed[v.to_s]? || [] of T) }
    result
  end

  class SoleItemExpectedError < Exception
    def initialize(message = "no item found")
      super(message)
    end
  end
end

class Array
  # Rails 8.1 semantics: sole IGNORES a passed block — it is "the only
  # element of this array" (0 or >1 elements raise SoleItemExpectedError).
  def sole(&block) : T
    raise Enumerable::SoleItemExpectedError.new("multiple items found") if size > 1
    raise Enumerable::SoleItemExpectedError.new("no item found") if empty?
    first
  end

  def sole : T
    raise Enumerable::SoleItemExpectedError.new("multiple items found") if size > 1
    raise Enumerable::SoleItemExpectedError.new("no item found") if empty?
    first
  end

  def find_sole(&block : T -> _) : T
    matches = self.select(&block)
    raise Enumerable::SoleItemExpectedError.new("multiple items found") unless matches.size == 1
    matches.first
  end

  def pluck(key : Symbol) : Array
    map { |e| e[key] }
  end

  def pluck(&block : T -> _) : Array
    map { |e| block.call(e) }
  end

  # pick() with no key/block: nil for empty (Ruby), TypeError otherwise
  # (P0: single-key pick; multi-key pick is a later addition).
  def pick
    return nil if empty?
    raise TypeError.new("wrong argument type (expected key or block)")
  end

  def pick(key : Symbol)
    first.try &.[key]?
  end

  def pick(&block : T -> _)
    first.try { |e| block.call(e) }
  end
end

struct Number
  def multiple_of?(number : Number) : Bool
    if self.is_a?(Int) && number.is_a?(Int)
      number == 0 ? false : self.remainder(number.as(Int)) == 0
    else
      quotient = to_f / number.to_f
      (quotient - quotient.round).abs < 1e-9
    end
  end
end

struct Int
  # Duration builders. NOTE: seconds..weeks keep the stdlib Time::Span
  # semantics — shadowing them breaks the stdlib itself (fiber pools use
  # `5.minutes` as a Span). Rails calendar units (months/years/fortnights)
  # return ActiveSupport::Duration; Span gets the Rails verbs
  # (ago/since/from_now/in_milliseconds) in time_ext.cr.
  def second : Time::Span
    seconds
  end

  def minute : Time::Span
    minutes
  end

  def hour : Time::Span
    hours
  end

  def day : Time::Span
    days
  end

  def week : Time::Span
    weeks
  end

  def fortnights : ActiveSupport::Duration
    ActiveSupport::Duration.new([{:weeks, to_i64 * 2}])
  end

  def fortnight : ActiveSupport::Duration
    fortnights
  end

  def months : ActiveSupport::Duration
    ActiveSupport::Duration.new([{:months, to_i64}])
  end

  def month : ActiveSupport::Duration
    months
  end

  def years : ActiveSupport::Duration
    ActiveSupport::Duration.new([{:years, to_i64}])
  end

  def year : ActiveSupport::Duration
    years
  end

  # Byte units (return Int64 — 1.exabyte overflows Int32).
  def byte : Int64
    to_i64
  end

  def bytes : Int64
    to_i64
  end

  def kilobyte : Int64
    to_i64 * 1024
  end

  def kilobytes : Int64
    kilobyte
  end

  def megabyte : Int64
    kilobyte * 1024
  end

  def megabytes : Int64
    megabyte
  end

  def gigabyte : Int64
    megabyte * 1024
  end

  def gigabytes : Int64
    gigabyte
  end

  def terabyte : Int64
    gigabyte * 1024
  end

  def terabytes : Int64
    terabyte
  end

  def petabyte : Int64
    terabyte * 1024
  end

  def petabytes : Int64
    petabyte
  end

  def exabyte : Int64
    petabyte * 1024
  end

  def exabytes : Int64
    exabyte
  end
end

struct Time
  def +(other : ActiveSupport::Duration) : Time
    other.add_to(self, 1)
  end

  def -(other : ActiveSupport::Duration) : Time
    other.add_to(self, -1)
  end
end

struct Time::Span
  # Rails verbs on stdlib spans (2.days.ago, 3.hours.from_now, ...).
  def ago : Time
    Time.local - self
  end

  def until : Time
    ago
  end

  def since : Time
    Time.local + self
  end

  def from_now : Time
    since
  end

  def in_milliseconds : Int64
    total_milliseconds.to_i64
  end

  def ==(other : Int) : Bool
    total_seconds.to_i64 == other
  end
end
