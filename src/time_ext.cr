# Time core_ext: Rails date/time math on Crystal Time (verified against
# oracle/expected.yml). Crystal has no Date class — the Rails Date API
# surface lives on Time for now (P0 scope).

module ActiveSupport
  class TimeZone
    getter name : String
    getter location : Time::Location

    def initialize(@name : String)
      @location = Time::Location.load(@name)
    end

    def parse(str : String, format : String = "%F %T") : TimeWithZone
      TimeWithZone.new(Time.parse(str, format, location), self)
    end

    # Simultaneous "now" in this zone (Rails TimeZone#now).
    def now : TimeWithZone
      TimeWithZone.new(Time.local.in(location), self)
    end

    def utc_offset(at : Time) : Int32
      at.in(location).offset
    end

    def formatted_offset(at : Time, colon : Bool = true) : String
      TimeWithZone.format_offset(at.in(location).offset.total_seconds.to_i32, colon)
    end

    def ==(other : TimeZone) : Bool
      name == other.name
    end
  end

  struct TimeWithZone
    getter zone : TimeZone

    def initialize(@time : Time, @zone : TimeZone)
    end

    def self.format_offset(offset : Int32, colon : Bool = true) : String
      sign = offset < 0 ? "-" : "+"
      total = offset.abs
      hours = total // 3600
      minutes = (total % 3600) // 60
      colon ? sprintf("%s%02d:%02d", sign, hours, minutes) : sprintf("%s%02d%02d", sign, hours, minutes)
    end

    def utc : Time
      @time.in(Time::Location::UTC)
    end

    def time : Time
      @time
    end

    def localtime : Time
      @time.in(Time::Location.local)
    end

    def utc_offset : Int32
      @time.offset
    end

    def formatted_offset(colon : Bool = true) : String
      TimeWithZone.format_offset(utc_offset, colon)
    end

    # Rails name for the zone getter (TimeZone object).
    def time_zone : TimeZone
      @zone
    end

    def in_time_zone(name : (String | TimeZone)? = nil) : TimeWithZone
      return self if name.nil?
      zone = name.is_a?(TimeZone) ? name : TimeZone.new(name)
      return self if zone == @zone
      TimeWithZone.new(utc.in(zone.location), zone)
    end

    # --- comparisons: always on the UTC instant -------------------------

    def <=>(other : TimeWithZone) : Int32
      utc <=> other.utc
    end

    def <=>(other : Time) : Int32
      utc <=> other
    end

    def ==(other : TimeWithZone) : Bool
      utc == other.utc
    end

    def ==(other : Time) : Bool
      utc == other
    end

    # --- arithmetic ------------------------------------------------------

    def +(other : Time::Span) : TimeWithZone
      since(other.total_seconds)
    end

    def +(seconds : Int | Float) : TimeWithZone
      since(seconds)
    end

    # TimeWithZone - TimeWithZone → seconds between the UTC instants.
    def -(other : TimeWithZone) : Float64
      (utc - other.utc).total_seconds
    end

    def -(other : Time::Span) : TimeWithZone
      ago(other.total_seconds)
    end

    def -(seconds : Int | Float) : TimeWithZone
      ago(seconds)
    end

    def since(seconds : Int | Float) : TimeWithZone
      TimeWithZone.new((utc + Time::Span.new(seconds: seconds.to_i64)).in(@zone.location), @zone)
    end

    def ago(seconds : Int | Float) : TimeWithZone
      since(-seconds)
    end

    # --- formatting ------------------------------------------------------

    # strftime on the zoned (wall-clock) time, like Rails (offset-aware).
    def strftime(format : String) : String
      time.to_s(format)
    end

    # Ruby Time#to_s lookalike: wall clock + offset ("+0100"/"UTC").
    def to_s : String
      offset = @zone.name == "UTC" ? "UTC" : formatted_offset(false)
      "#{time.to_s("%F %T")} #{offset}"
    end

    def to_fs(format : Symbol = :default) : String
      case format
      when :db      then utc.to_fs(:db)
      when :default then to_s
      else               time.to_fs(format)
      end
    end

    def to_fs(format : String) : String
      strftime(format)
    end

    def to_formatted_s(format : Symbol = :default) : String
      to_fs(format)
    end
  end
end

struct Time
  MONTH_NAMES   = %w(January February March April May June July August September October November December)
  ABBR_MONTHS   = %w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  DAY_NAMES     = %w(Sunday Monday Tuesday Wednesday Thursday Friday Saturday)
  ABBR_DAYS     = %w(Sun Mon Tue Wed Thu Fri Sat)

  @@zone : ActiveSupport::TimeZone?

  # Fiber-local zone overrides installed by Time.use_zone: a request (its
  # own fiber) can switch zone for the duration of a block without
  # touching the process-global default. Crystal has no fiber-locals, so
  # this is a simple registry keyed by Fiber.
  @@fiber_zones = {} of Fiber => ActiveSupport::TimeZone

  def self.zone : ActiveSupport::TimeZone?
    @@fiber_zones[Fiber.current]? || @@zone
  end

  def self.zone=(name : String) : ActiveSupport::TimeZone
    @@zone = ActiveSupport::TimeZone.new(name)
  end

  def self.zone=(zone : ActiveSupport::TimeZone) : ActiveSupport::TimeZone
    @@zone = zone
  end

  def self.zone=(zone : Nil) : Nil
    @@zone = nil
  end

  # Time.use_zone("Europe/Berlin") { ... } — set the zone for the current
  # fiber only, restore the previous zone afterwards (even on raise).
  def self.use_zone(zone : String | ActiveSupport::TimeZone, &)
    tz = zone.is_a?(String) ? ActiveSupport::TimeZone.new(zone) : zone
    fiber = Fiber.current
    previous = @@fiber_zones[fiber]?
    @@fiber_zones[fiber] = tz
    begin
      yield
    ensure
      if previous
        @@fiber_zones[fiber] = previous
      else
        @@fiber_zones.delete(fiber)
      end
    end
  end

  # Time.zone ? Time.zone.now : Time.local (Rails Time.current).
  def self.current : Time | ActiveSupport::TimeWithZone
    zone ? zone.not_nil!.now : Time.local
  end

  def in_time_zone(name : (String | ActiveSupport::TimeZone)? = nil) : ActiveSupport::TimeWithZone
    zone = name.is_a?(ActiveSupport::TimeZone) ? name : (name ? ActiveSupport::TimeZone.new(name) : (Time.zone || ActiveSupport::TimeZone.new("UTC")))
    ActiveSupport::TimeWithZone.new(self.in(zone.location), zone)
  end

  # --- day-of-week predicates -------------------------------------------

  # Ruby-style wday: 0 = Sunday ... 6 = Saturday.
  def wday : Int32
    day_of_week.value.remainder(7)
  end

  {% for day, index in %w(sunday monday tuesday wednesday thursday friday saturday) %}
    def {{day.id}}? : Bool
      wday == {{index}}
    end
  {% end %}

  # --- beginning/end of periods -------------------------------------------

  def beginning_of_day : Time
    at_beginning_of_day
  end

  def end_of_day : Time
    at_end_of_day
  end

  def middle_of_day : Time
    Time.local(year, month, day, 12, 0, 0, nanosecond: 0, location: location)
  end

  def mid_day : Time
    middle_of_day
  end

  def noon : Time
    middle_of_day
  end

  def beginning_of_week(week_start = :monday) : Time
    at_beginning_of_week(Time.day_of_week(week_start))
  end

  def end_of_week(week_start = :monday) : Time
    (at_beginning_of_week(Time.day_of_week(week_start)) + 6.days).at_end_of_day
  end

  def beginning_of_month : Time
    at_beginning_of_month
  end

  def end_of_month : Time
    at_end_of_month
  end

  def beginning_of_quarter : Time
    first_quarter_month = ((month - 1) // 3) * 3 + 1
    Time.local(year, first_quarter_month, 1, 0, 0, 0, nanosecond: 0, location: location)
  end

  def end_of_quarter : Time
    last_quarter_month = ((month - 1) // 3) * 3 + 3
    Time.local(year, last_quarter_month, Time.days_in_month(year, last_quarter_month),
      23, 59, 59, nanosecond: 999_999_999, location: location)
  end

  def beginning_of_year : Time
    at_beginning_of_year
  end

  def end_of_year : Time
    at_end_of_year
  end

  def all_day : Range(Time, Time)
    beginning_of_day..end_of_day
  end

  def all_week(week_start = :monday) : Range(Time, Time)
    beginning_of_week(week_start)..end_of_week(week_start)
  end

  def all_month : Range(Time, Time)
    beginning_of_month..end_of_month
  end

  def all_quarter : Range(Time, Time)
    beginning_of_quarter..end_of_quarter
  end

  def all_year : Range(Time, Time)
    beginning_of_year..end_of_year
  end

  # --- relative shifts ------------------------------------------------------

  def ago(seconds : Int | Float) : Time
    self - Time::Span.new(seconds: seconds.to_i64)
  end

  def since(seconds : Int | Float) : Time
    self + Time::Span.new(seconds: seconds.to_i64)
  end

  def in(seconds : Int | Float) : Time
    since(seconds)
  end

  def yesterday : Time
    shift_calendar_months(0, -1)
  end

  def tomorrow : Time
    shift_calendar_months(0, 1)
  end

  def prev_day : Time
    yesterday
  end

  def next_day : Time
    tomorrow
  end

  def next_week(given_day = :monday) : Time
    target = Time.day_of_week(given_day)
    base = at_beginning_of_week(Time.day_of_week(:monday)) + 7.days
    offset = (target.value - 1).remainder(7)
    (base + offset.days).at_beginning_of_day
  end

  def prev_week(given_day = :monday) : Time
    target = Time.day_of_week(given_day)
    base = at_beginning_of_week(Time.day_of_week(:monday)) - 7.days
    offset = (target.value - 1).remainder(7)
    (base + offset.days).at_beginning_of_day
  end

  def next_month : Time
    shift_calendar_months(1)
  end

  def prev_month : Time
    shift_calendar_months(-1)
  end

  def next_year : Time
    shift_calendar_months(12)
  end

  def prev_year : Time
    shift_calendar_months(-12)
  end

  def months_ago(months : Int) : Time
    shift_calendar_months(-months)
  end

  def months_since(months : Int) : Time
    shift_calendar_months(months)
  end

  def years_ago(years : Int) : Time
    shift_calendar_months(-years * 12)
  end

  def years_since(years : Int) : Time
    shift_calendar_months(years * 12)
  end

  def next_occurring(day_of_week) : Time
    target = Time.day_of_week(day_of_week)
    days_ahead = (target.value - wday).remainder(7)
    days_ahead += 7 if days_ahead <= 0
    shift_calendar_months(0, days_ahead)
  end

  def prev_occurring(day_of_week) : Time
    target = Time.day_of_week(day_of_week)
    days_back = (wday - target.value).remainder(7)
    days_back += 7 if days_back <= 0
    shift_calendar_months(0, -days_back)
  end

  # advance(years:, months:, weeks:, days:, hours:, minutes:, seconds:)
  def advance(years : Int = 0, months : Int = 0, weeks : Int = 0, days : Int = 0,
              hours : Int = 0, minutes : Int = 0, seconds : Int = 0) : Time
    shifted = shift_calendar_months(months + years * 12, days + weeks * 7)
    span = Time::Span.new(hours: hours, minutes: minutes, seconds: seconds)
    span == Time::Span.zero ? shifted : shifted + span
  end

  def change(year = nil, month = nil, day = nil, hour = nil, min = nil, sec = nil,
             usec = nil, nsec = nil) : Time
    new_nsec = nsec || (usec ? usec.to_i * 1000 : self.nanosecond)
    Time.local(year || self.year, month || self.month, day || self.day,
      hour || self.hour, min || self.minute, sec || self.second,
      nanosecond: new_nsec, location: location)
  end

  def past? : Bool
    self < Time.local
  end

  def future? : Bool
    self > Time.local
  end

  def today? : Bool
    at_beginning_of_day == Time.local.at_beginning_of_day
  end

  # to_fs: :db/:short/:long/:iso8601/:number or strftime-ish String.
  def to_fs(format : Symbol = :default) : String
    case format
    when :db      then sprintf("%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
    when :number  then sprintf("%04d%02d%02d%02d%02d%02d", year, month, day, hour, minute, second)
    when :time    then sprintf("%02d:%02d", hour, minute)
    when :short   then sprintf("%02d %s %02d:%02d", day, ABBR_MONTHS[month - 1], hour, minute)
    when :long    then sprintf("%s %02d, %04d %02d:%02d", MONTH_NAMES[month - 1], day, year, hour, minute)
    when :iso8601 then to_s("%FT%T%:z").sub("+00:00", "Z")
    else               to_s
    end
  end

  def to_fs(format : String) : String
    to_s(format)
  end

  def to_formatted_s(format : Symbol = :default) : String
    to_fs(format)
  end

  # Calendar-aware month shift with day clamping (2026-03-31 - 1 month
  # → 2026-02-28), preserves time-of-day and location.
  def shift_calendar_months(months : Int, days : Int = 0) : Time
    total = year * 12 + (month - 1) + months
    new_year = total // 12
    new_month = total.modulo(12) + 1
    dim = Time.days_in_month(new_year, new_month)
    new_day = day > dim ? dim : day
    result = Time.local(new_year, new_month, new_day, hour, minute, second,
      nanosecond: nanosecond, location: location)
    days == 0 ? result : result + Time::Span.new(days: days)
  end

  def self.day_of_week(name : Symbol | String | Time::DayOfWeek) : Time::DayOfWeek
    return name if name.is_a?(Time::DayOfWeek)
    value = name.to_s.capitalize
    {% for const in %w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday) %}
      return Time::DayOfWeek::{{const.id}} if value == {{const}}
    {% end %}
    raise ArgumentError.new("invalid day of week: #{name}")
  end
end
