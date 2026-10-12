# Minimal calendar date (year-month-day) — used by ActiveJob argument
# serialization to mirror Ruby's Date round-trip ("YYYY-MM-DD").
struct Date
  include Comparable(self)

  getter year : Int32
  getter month : Int32
  getter day : Int32

  def initialize(@year : Int32, @month : Int32, @day : Int32)
  end

  # "2026-01-02" — same as Ruby Date#to_s / iso8601.
  def to_s(io : IO) : Nil
    io << @year.to_s.rjust(4, '0') << '-' << @month.to_s.rjust(2, '0') << '-' << @day.to_s.rjust(2, '0')
  end

  def self.parse(str : String) : self
    parts = str.split("-")
    new(parts[0].to_i32, parts[1].to_i32, parts[2].to_i32)
  end

  def <=>(other : self) : Int32
    {year, month, day} <=> {other.year, other.month, other.day}
  end
end
