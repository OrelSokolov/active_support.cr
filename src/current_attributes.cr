# CurrentAttributes — port of ActiveSupport::CurrentAttributes (Rails 8.x).
#
# `class Current < ActiveSupport::CurrentAttributes` with typed
# attributes; accessors are class-level (`Current.user`), values live in
# FIBER-LOCAL storage (Rails: Executor/isolated per request; here: each
# connection/request fiber of serverx gets its own store, reset per
# request cycle by the framework — `ActiveSupport::CurrentAttributes.
# reset_all`, wired into the request dispatch by railties_cr).
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
#   clears the underlying storage, values must go through it.
# - storage hangs off `Fiber.current` (std lib class reopened below),
#   so interleaved fibers can't see each other's attributes; entries
#   die with the fiber. Values are kept in HeapBox wrappers — a typed
#   class ivar the GC traces (raw Void* would be invisible to the GC
#   and the boxed object could be collected while referenced only
#   here).

module ActiveSupport
  # GC-traceable cell for one CurrentAttributes value (see
  # CurrentAttributes): @value is a typed ivar of a heap class, so the
  # collector keeps the stored object alive through the store.
  class CurrentBox(T)
    property value : T

    def initialize(@value : T)
    end
  end

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
        {% ca_key = "#{key.id}.#{name.id}" %}

        def self.{{name.id}} : {{ type }}
          if (box = Fiber.current.__current_attributes_store?[{{ ca_key }}]?)
            box.as(ActiveSupport::CurrentBox({{ type }})).value
          else
            nil.as({{ type }})
          end
        end

        def self.{{name.id}}=(value : {{ type }}) : {{ type }}
          Fiber.current.__current_attributes_store[{{ ca_key }}] =
            ActiveSupport::CurrentBox({{ type }}).new(value)
          value
        end
      {% end %}

      def self.reset : Nil
        if (store = Fiber.current.__current_attributes_store?)
          {% for triple in ActiveSupport::CurrentAttributes::ATTRS.select { |t| t[0] == @type.stringify } %}
            {% ca_key = "#{@type.stringify}.#{triple[1].stringify}" %}
            store.delete({{ ca_key }})
          {% end %}
        end
        nil
      end
    end
  end
end

class Fiber
  # Per-fiber CurrentAttributes storage: "<Class>.<attr>" → boxed value.
  # Not a public API — belongs to ActiveSupport::CurrentAttributes.
  @__current_attributes_store : Hash(String, ActiveSupport::CurrentBox)?

  def __current_attributes_store : Hash(String, ActiveSupport::CurrentBox)
    @__current_attributes_store ||= {} of String => ActiveSupport::CurrentBox
  end

  def __current_attributes_store? : Hash(String, ActiveSupport::CurrentBox)?
    @__current_attributes_store
  end
end

# Generated after the whole program is parsed so CLASSES is complete.
macro finished
  module ActiveSupport
    abstract class CurrentAttributes
      # Rails' Executor semantics: reset every CurrentAttributes class.
      # Called by the request dispatcher (railties_cr) between requests —
      # resets the CURRENT fiber's storage (request dispatch and its
      # renders run on the same fiber).
      def self.reset_all : Nil
        {% for c in ActiveSupport::CurrentAttributes::CLASSES %}
          {{ c.id }}.reset
        {% end %}
        nil
      end
    end
  end
end
