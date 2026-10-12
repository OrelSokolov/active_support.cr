# Structural specs for Concern, delegate, Notifications (no oracle —
# these APIs are behavioral; reference suites live in oracle/rails-tests/).

require "spec"
require "../src/active_support_cr"

module Greeting
  include ActiveSupport::Concern

  # Rails: included do ... end → Crystal: macro included (hook macros
  # take no parameters — documented deviation, see src/concern.cr).
  macro included
    extend_class_methods!
    property greeting : String = "hello"
  end

  class_methods do
    def default_greeting : String
      "class-level hello"
    end
  end
end

module Farewell
  include ActiveSupport::Concern

  macro included
    property farewell : String = "bye"
  end
end

class PersonWithConcerns
  include Greeting
  include Farewell
end

describe "ActiveSupport::Concern" do
  it "macro included blocks apply to the including class" do
    p = PersonWithConcerns.new
    p.greeting.should eq("hello")
    p.farewell.should eq("bye")
  end

  it "extends class_methods onto the class" do
    PersonWithConcerns.default_greeting.should eq("class-level hello")
  end

  it "blocks define instance state per class" do
    p = PersonWithConcerns.new
    p.greeting = "hi"
    p.greeting.should eq("hi")
    PersonWithConcerns.new.greeting.should eq("hello")
  end
end

class Author
  def name : String
    "Ada"
  end
end

class Book
  def author : Author
    Author.new
  end

  delegate :name, to: :author
end

class MaybeBook
  def author : Author?
    nil
  end

  delegate :name, to: :author, allow_nil: true
end

class PrefixedBook
  def author : Author
    Author.new
  end

  delegate :name, to: :author, prefix: true
  delegate :name, to: :author, prefix: :writer
end

describe "delegate" do
  it "forwards to the target method" do
    Book.new.name.should eq("Ada")
  end

  it "allow_nil returns nil for nil target" do
    MaybeBook.new.name.should be_nil
  end

  it "prefix: true and prefix: :writer" do
    b = PrefixedBook.new
    b.author_name.should eq("Ada")
    b.writer_name.should eq("Ada")
  end
end

describe "ActiveSupport::Notifications" do
  it "instrument publishes to exact-name subscribers" do
    events = [] of String
    ActiveSupport::Notifications.subscribe("test.exact") { |e| events << e.name }
    result = ActiveSupport::Notifications.instrument("test.exact", {"key" => 1} of String => ActiveSupport::Any) { 42 }
    result.should eq(42)
    events.should eq(["test.exact"])
    ActiveSupport::Notifications.clear
  end

  it "prefix wildcard subscribers receive dotted children" do
    events = [] of String
    ActiveSupport::Notifications.subscribe("sql.*") { |e| events << e.name }
    ActiveSupport::Notifications.instrument("sql.query") { }
    ActiveSupport::Notifications.instrument("other.query") { }
    events.should eq(["sql.query"])
    ActiveSupport::Notifications.clear
  end

  it "event exposes duration and payload" do
    received = nil
    ActiveSupport::Notifications.subscribe("dur.ev") { |e| received = e }
    ActiveSupport::Notifications.instrument("dur.ev", {"a" => "b"} of String => ActiveSupport::Any) { sleep 5.milliseconds }
    ev = received.should_not be_nil
    ev.payload["a"].should eq("b")
    ev.duration.should be >= 4.0
    ActiveSupport::Notifications.clear
  end

  it "blockless instrument still publishes" do
    events = [] of String
    ActiveSupport::Notifications.subscribe { |e| events << e.name }
    ActiveSupport::Notifications.instrument("no.block")
    events.should eq(["no.block"])
    ActiveSupport::Notifications.clear
  end
end
