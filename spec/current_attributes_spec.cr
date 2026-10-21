# Specs for ActiveSupport::CurrentAttributes (behavioral — no oracle:
# the reference gem's own specs exercise Ruby instance semantics that
# the port intentionally deviates from, see src/current_attributes.cr).

require "spec"
require "../src/active_support_cr"

class CASpecUser
  property name : String = "david"
end

class CASpecRequest
  property host : String = "example.com"
end

class CASpecCurrent < ActiveSupport::CurrentAttributes
  attribute user: CASpecUser?, request: CASpecRequest?
end

class CASpecOther < ActiveSupport::CurrentAttributes
  attribute flag: Bool?

  attribute token: String?
end

describe ActiveSupport::CurrentAttributes do
  after_each do
    ActiveSupport::CurrentAttributes.reset_all
  end

  it "defaults attributes to nil" do
    CASpecCurrent.user.should be_nil
    CASpecCurrent.request.should be_nil
  end

  it "stores and returns class-level values" do
    user = CASpecUser.new
    CASpecCurrent.user = user
    CASpecCurrent.user.same?(user).should be_true
    CASpecCurrent.user.try(&.name).should eq "david"
  end

  it "resets a single class without touching others" do
    CASpecCurrent.user = CASpecUser.new
    CASpecOther.flag = true
    CASpecCurrent.reset
    CASpecCurrent.user.should be_nil
    CASpecOther.flag.should be_true
  end

  it "reset accumulates across multiple attribute calls" do
    CASpecOther.flag = true
    CASpecOther.token = "t"
    CASpecOther.reset
    CASpecOther.flag.should be_nil
    CASpecOther.token.should be_nil
  end

  it "reset_all clears every CurrentAttributes class" do
    CASpecCurrent.user = CASpecUser.new
    CASpecCurrent.request = CASpecRequest.new
    CASpecOther.flag = true
    CASpecOther.token = "t"
    ActiveSupport::CurrentAttributes.reset_all
    CASpecCurrent.user.should be_nil
    CASpecCurrent.request.should be_nil
    CASpecOther.flag.should be_nil
    CASpecOther.token.should be_nil
  end

  it "re-assigns after reset" do
    CASpecCurrent.user = CASpecUser.new
    CASpecCurrent.reset
    user = CASpecUser.new
    CASpecCurrent.user = user
    CASpecCurrent.user.same?(user).should be_true
  end
end
