# Ruby-compat attr_* aliases for developers coming to Crails from Rails.
#
#   Ruby                    idiomatic Crystal     this alias
#   attr_reader :foo        getter foo            attr_reader :foo
#   attr_writer :foo        setter foo            attr_writer :foo
#   attr_accessor :foo      property foo          attr_accessor :foo
#
# Accepts Ruby-style symbols, bare names, and typed declarations with
# defaults (delegated to the stdlib getter/setter/property macros):
#
#   attr_reader :body, :content_type
#   attr_accessor name : String = "anon", level : Int32 = 0

class Object
  macro attr_reader(*attrs)
    {% for attr in attrs %}
      {% if attr.is_a?(SymbolLiteral) %}
        getter {{ attr.id }}
      {% else %}
        getter {{ attr }}
      {% end %}
    {% end %}
  end

  macro attr_writer(*attrs)
    {% for attr in attrs %}
      {% if attr.is_a?(SymbolLiteral) %}
        setter {{ attr.id }}
      {% else %}
        setter {{ attr }}
      {% end %}
    {% end %}
  end

  macro attr_accessor(*attrs)
    {% for attr in attrs %}
      {% if attr.is_a?(SymbolLiteral) %}
        property {{ attr.id }}
      {% else %}
        property {{ attr }}
      {% end %}
    {% end %}
  end
end
