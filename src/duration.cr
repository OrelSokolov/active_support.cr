# ActiveSupport::Duration — port of Rails Duration (2.days, 3.months, ...).
#
# Shadow semantics note: Int#seconds/#minutes/#hours/#days/#weeks shadow
# the stdlib Time::Span helpers on purpose — the Rails API returns a
# Duration (calendar-aware months/years, Rails inspect format). Stdlib
# spans are still reachable via Time::Span.new or 5.seconds.to_span.

module ActiveSupport
  struct Duration
    PART_ORDER = {:years, :months, :weeks, :days, :hours, :minutes, :seconds}

    SECONDS_PER_PART = {
      seconds: 1_i64,
      minutes: 60_i64,
      hours:   3_600_i64,
      days:    86_400_i64,
      weeks:   604_800_i64,
      # Calendar parts fall back to the Rails approximations (30d/365d)
      # for to_i; calendar-aware math happens in Time#+/-.
      months:  2_592_000_i64,
      years:   31_536_000_i64,
    }

    getter parts : Array(Tuple(Symbol, Int64))
    getter value : Int64

    def initialize(parts : Array(Tuple(Symbol, Int64)))
      @parts = Duration.normalize(parts)
      @value = @parts.sum { |part, n| n * SECONDS_PER_PART[part] }
    end

    def self.normalize(parts) : Array(Tuple(Symbol, Int64))
      summed = Hash(Symbol, Int64).new { |h, k| h[k] = 0_i64 }
      parts.each { |part, n| summed[part] += n unless n == 0 }
      ordered = [] of Tuple(Symbol, Int64)
      PART_ORDER.each do |part|
        n = summed[part]?
        ordered << {part, n} if n && n != 0
      end
      ordered
    end

    def self.new(*parts : Tuple(Symbol, Int64))
      new(parts.to_a)
    end

    def +(other : Duration) : Duration
      Duration.new(parts + other.parts)
    end

    def -(other : Duration) : Duration
      Duration.new(parts + other.parts.map { |part, n| {part, -n} })
    end

    def ==(other : Duration) : Bool
      value == other.value
    end

    def ==(other : Int) : Bool
      value == other
    end

    def !=(other : Duration) : Bool
      value != other.value
    end

    def to_i : Int64
      @value
    end

    def in_milliseconds : Int64
      @value * 1000
    end

    def to_span : Time::Span
      Time::Span.new(seconds: @value)
    end

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

    # Rails inspect format: "2 days", "2 days and 6 hours",
    # "1 day, 2 hours and 3 minutes".
    def to_s : String
      case parts.size
      when 0 then "0 seconds"
      when 1
        part, n = parts.first
        "#{n} #{Duration.name_part(part, n)}"
      else
        fragments = parts.map { |part, n| "#{n} #{Duration.name_part(part, n)}" }
        "#{fragments[0...-1].join(", ")} and #{fragments.last}"
      end
    end

    def inspect : String
      to_s
    end

    def self.name_part(part : Symbol, n : Int64) : String
      name = part.to_s.chomp('s')
      n == 1 ? name : "#{name}s"
    end

    # Sums of specific parts.
    def part_value(part : Symbol) : Int64
      found = parts.find { |p, _| p == part }
      found ? found[1] : 0_i64
    end

    def calendar_months : Int64
      part_value(:months) + part_value(:years) * 12
    end

    def fixed_seconds : Int64
      parts.sum do |part, n|
        {:weeks, :days, :hours, :minutes, :seconds}.includes?(part) ? n * SECONDS_PER_PART[part] : 0_i64
      end
    end

    def add_to(time : Time, sign : Int32 = 1) : Time
      result = time
      months = calendar_months * sign
      result = result.shift_calendar_months(months) unless months == 0
      secs = fixed_seconds * sign
      result += Time::Span.new(seconds: secs) unless secs == 0
      result
    end
  end
end
