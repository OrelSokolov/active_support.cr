# Specs for the Ruby-compat attr_reader/attr_writer/attr_accessor aliases:
# Ruby-style symbol args, bare names, and typed declarations with defaults.

require "spec"
require "../src/active_support_cr"

class AttrReaderUser
  attr_reader :body, :content_type
  @body = "hello"
  @content_type = "text/html"
end

class AttrTypedReader
  attr_reader hits : Int32 = 0
end

class AttrWriterUser
  attr_writer :secret
  @secret : String = ""

  def peek : String
    @secret
  end
end

class AttrAccessorUser
  attr_accessor name : String = "anon", :flag
  @flag = true
end

describe "attr_* aliases" do
  it "attr_reader accepts Ruby-style symbols" do
    user = AttrReaderUser.new
    user.body.should eq("hello")
    user.content_type.should eq("text/html")
  end

  it "attr_reader passes typed declarations through to getter" do
    AttrTypedReader.new.hits.should eq(0)
  end

  it "attr_writer generates a Ruby-style assignment method" do
    user = AttrWriterUser.new
    user.secret = "shh"
    user.peek.should eq("shh")
  end

  it "attr_accessor mixes symbols and typed declarations" do
    user = AttrAccessorUser.new
    user.name.should eq("anon")
    user.name = "bob"
    user.name.should eq("bob")
    user.flag.should be_true
    user.flag = false
    user.flag.should be_false
  end
end
