# ActiveSupport::TimeFormats — port of Rails 8.2's global time-format
# registry (active_support/time_formats.rb). Formats registered here are
# resolved by Time#to_fs / TimeWithZone#to_fs BEFORE the built-in formats
# (Rails merges registered entries into the same list, so a registration
# shadows a same-named builtin).
#
# Values are either a strftime String or a Proc(Time, String) — Rails
# lambdas receive the time itself and their result goes through #to_s,
# so Crystal blocks return the final String directly:
#
#   ActiveSupport::TimeFormats.register(:epoch, ->(time : Time) {
#     ((time.to_f * 1000).to_i).to_s
#   })
#
# TimeWithZone#to_fs calls a proc formatter with the UTC instant and
# strftime-formats on the wall-clock time, matching Rails' zoned output.

module ActiveSupport
  module TimeFormats
    alias Formatter = String | Proc(Time, String)

    @@list = {} of Symbol => Formatter

    def self.register(name : Symbol, format : String) : Nil
      @@list[name] = format
    end

    def self.register(name : Symbol, formatter : Proc(Time, String)) : Nil
      @@list[name] = formatter
    end

    def self.lookup(name : Symbol) : Formatter?
      @@list[name]?
    end

    def self.list : Hash(Symbol, Formatter)
      @@list.dup
    end

    def self.clear : Nil
      @@list.clear
    end
  end
end
