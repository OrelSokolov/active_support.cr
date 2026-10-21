# CurrentAttributes — port of ActiveSupport::CurrentAttributes (Rails 8.x).
#
# `class Current < ActiveSupport::CurrentAttributes` with typed
# attributes; accessors are class-level (`Current.user`), values live in
# process-global class vars reset per request cycle by the framework
# (`ActiveSupport::CurrentAttributes.reset_all`, wired into the request
# dispatch by railties_cr).
#
# Deviations from Rails (Crystal constraints):
# - `attribute user: User?` — typed named args; Ruby's untyped
#   `attribute :user, :request` can't map to Crystal class vars. Types
#   MUST be nilable (`reset` assigns nil).
# - instance-level API (`Current.instance`, overridable attribute
#   writers with `super`), `set(**attrs) { }` and before_reset/
#   after_reset callbacks are not ported — the reference app does not
#   use them. Override setters by defining `self.foo=` AFTER the
#   `attribute` call (last definition wins) — but then `reset` still
#   clears the underlying class var, values must go through it.
# - P0 limitation: storage is process-global, not fiber/thread-isolated.
#   Safe while one request is dispatched at a time; interleaved
#   concurrent requests would see each other's attributes (same class
#   of limitation as the port's other global request caches).

module ActiveSupport
  abstract class CurrentAttributes
    # Compile-time registry of all CurrentAttributes subclasses
    # (filled by `macro inherited`), consumed by `reset_all` — the
    # top-level `macro finished` below generates it after every class
    # in the program is defined.
    CLASSES = [] of TypeNode

    # Flat compile-time registry of declared attributes:
    # {class name, attribute name, attribute type}. A per-class
    # constant can't be read back by a later macro expansion of the
    # same class body, so per-class lists live here, keyed by name
    # (same idiom as ActionController::FILTERS).
    ATTRS = [] of {String, Symbol, TypeNode}

    macro inherited
      {% ActiveSupport::CurrentAttributes::CLASSES << @type %}
    end

    # Declare typed attributes: `attribute user: User?, request: HTTP::Request?`.
    # Generates class-level getter/setter per attribute plus `self.reset`
    # (nils every attribute of this class, across all `attribute` calls).
    macro attribute(**attrs)
      {% key = @type.stringify %}
      {% for name, type in attrs %}
        {% unless type.is_a?(Path) || type.is_a?(Generic) || type.is_a?(Union) %}
          {% raise "attribute #{name}: expected a nilable type like `user: User?`" %}
        {% end %}
        {% ActiveSupport::CurrentAttributes::ATTRS << {key, name, type} %}
        @@__ca_{{name.id}} : {{ type }}

        def self.{{name.id}} : {{ type }}
          @@__ca_{{name.id}}
        end

        def self.{{name.id}}=(value : {{ type }}) : {{ type }}
          @@__ca_{{name.id}} = value
        end
      {% end %}

      def self.reset : Nil
        {% for triple in ActiveSupport::CurrentAttributes::ATTRS.select { |t| t[0] == @type.stringify } %}
          @@__ca_{{triple[1].id}} = nil.as({{ triple[2] }})
        {% end %}
        nil
      end
    end
  end
end

# Generated after the whole program is parsed so CLASSES is complete.
macro finished
  module ActiveSupport
    abstract class CurrentAttributes
      # Rails' Executor semantics: reset every CurrentAttributes class.
      # Called by the request dispatcher (railties_cr) between requests.
      def self.reset_all : Nil
        {% for c in ActiveSupport::CurrentAttributes::CLASSES %}
          {{ c.id }}.reset
        {% end %}
        nil
      end
    end
  end
end
