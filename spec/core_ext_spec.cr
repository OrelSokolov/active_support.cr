require "spec"
require "../src/active_support_cr"

describe "ActiveSupport core_ext (Iteration 0 slice)" do
  describe "blank?/present?" do
    it "strings" do
      "".blank?.should be_true
      "   ".blank?.should be_true
      "\t\n".blank?.should be_true
      "a".blank?.should be_false
      "a".present?.should be_true
      "".present?.should be_false
    end

    it "nil" do
      nil.blank?.should be_true
      nil.present?.should be_false
    end

    it "collections" do
      ([] of Int32).blank?.should be_true
      [1].blank?.should be_false
      ({} of String => String).blank?.should be_true
      {"" => ""}.blank?.should be_false
    end

    it "everything else is present" do
      0.blank?.should be_false
      false.blank?.should be_false
    end
  end

  describe "presence" do
    it "returns value when present, nil otherwise" do
      "".presence.should be_nil
      nil.presence.should be_nil
      "x".presence.should eq("x")
      0.presence.should eq(0)
    end
  end

  describe "try" do
    it "yields receiver when present" do
      "a".try(&.upcase).should eq("A")
    end

    it "returns nil for nil receiver without calling the block" do
      nil.try(&.upcase).should be_nil
    end
  end
end
