# ActiveSupport::Notifications — synchronous instrument/subscribe port.
#
# P0 semantics (mirrors the vendored oracle/rails-tests/notifications_test.rb
# where sync): instrument runs the block, publishes the event to every
# subscriber matching the name (exact match or prefix "sql.*" patterns
# are NOT globbed in P0 — exact or trailing `.*` suffix).

module ActiveSupport
  module Notifications
    class Event
      getter name : String
      getter payload : Hash(String, ActiveSupport::Any)
      getter time : Time
      getter end : Time?
      property transaction_id : String?

      def initialize(@name : String, payload : Hash(String, ActiveSupport::Any) = {} of String => ActiveSupport::Any)
        @payload = payload
        @time = Time.local
      end

      def end!
        @end = Time.local
      end

      def duration : Float64
        (@end || Time.local) - @time > Time::Span.zero ? ((@end || Time.local) - @time).total_milliseconds : 0.0
      end

      def payload_with(*extra : Tuple(String, ActiveSupport::Any)) : Hash(String, ActiveSupport::Any)
        @payload.merge(extra.to_h)
      end
    end

    @@subscribers = [] of Tuple(String?, Proc(Event, Nil))

    def self.instrument(name : String, payload : Hash(String, ActiveSupport::Any) = {} of String => ActiveSupport::Any)
      event = Event.new(name, payload)
      begin
        result = yield event
        publish(event)
        result
      rescue ex : Exception
        # Rails semantics: an exception escaping the instrumented block is
        # recorded on the payload, the event is still published, then the
        # exception is re-raised (rate_limit relies on this).
        event.payload["exception"] = "#{ex.class.name}: #{ex.message}"
        publish(event)
        raise ex
      end
    end

    def self.instrument(name : String)
      event = Event.new(name, {} of String => ActiveSupport::Any)
      publish(event)
      nil
    end

    def self.publish(event : Event)
      event.end!
      @@subscribers.each do |pattern, callback|
        next if pattern && !match?(pattern, event.name)
        callback.call(event)
      end
    end

    # subscribe("sql.query") { |event| ... } or subscribe { |event| ... }
    # (all events). Returns the subscriber object for unsubscribe.
    def self.subscribe(pattern : String | Nil = nil, &callback : Event -> _) : String
      wrapper = ->(event : Event) { callback.call(event); nil }
      @@subscribers << {pattern.as(String?), wrapper}
      "subscriber:#{pattern.inspect}:#{@@subscribers.size}"
    end

    def self.unsubscribe(subscriber : String)
      @@subscribers.reject! { |p, _| "subscriber:#{p.inspect}:#{@@subscribers.size}" == subscriber }
    end

    def self.subscribers : Array(Tuple(String?, Proc(Event, Nil)))
      @@subscribers
    end

    def self.clear
      @@subscribers.clear
    end

    private def self.match?(pattern : String, name : String) : Bool
      return true if pattern == name
      if pattern.ends_with?(".*")
        prefix = pattern.rchop(".*")
        name.starts_with?(prefix + ".")
      else
        false
      end
    end
  end
end
