# ActiveSupport::StringInquirer — port of Rails' String#inquiry
# (active_support/core_ext/string/inquiry.rb).
#
# Crystal's String is a primitive and cannot be subclassed, so the
# inquirer wraps the string instead of inheriting from it. The `name?`
# predicates are generated at compile time from method_missing; string
# equality/blankness/serialization delegate to the wrapped value.

module ActiveSupport
  struct StringInquirer
    getter string : String

    def initialize(@string : String)
    end

    def ==(other : String) : Bool
      @string == other
    end

    def !=(other : String) : Bool
      @string != other
    end

    def blank? : Bool
      @string.blank?
    end

    def present? : Bool
      @string.present?
    end

    def to_s : String
      @string
    end

    def to_s(io : IO) : Nil
      io << @string
    end

    def inspect(io : IO) : Nil
      io << @string.inspect
    end

    macro method_missing(call)
      {% if call.args.empty? && call.named_args.nil? && call.name.stringify.ends_with?('?') %}
        def {{call.name.id}} : Bool
          @string == {{call.name.stringify.gsub(/\?\z/, "")}}
        end
      {% else %}
        {% raise "StringInquirer: undefined method `#{call.name.id}` (inquiry predicates are `name?` only)" %}
      {% end %}
    end
  end
end

class String
  # "production".inquiry.production? # => true
  def inquiry : ActiveSupport::StringInquirer
    ActiveSupport::StringInquirer.new(self)
  end
end
