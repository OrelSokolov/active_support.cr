require "spec"
require "../src/active_support_cr"

FIXTURES = File.join(__DIR__, "fixtures")

def load_i18n_fixtures
  I18n.load_path = [File.join(FIXTURES, "en.yml"), File.join(FIXTURES, "ru.yml")]
end

describe "I18n" do
  before_each { load_i18n_fixtures }

  it "translates flat and nested keys" do
    I18n.t("hello").should eq("Hello")
    I18n.t("nav.dashboard").should eq("Dashboard")
  end

  it "interpolates %{name}" do
    I18n.t("greeting", name: "Ada").should eq("Hello, Ada!")
  end

  it "uses default when key missing" do
    I18n.t("nope", default: "fallback").should eq("fallback")
  end

  it "raises MissingTranslation without default" do
    expect_raises(I18n::MissingTranslation) { I18n.t("nope") }
  end

  it "switches locales" do
    I18n.locale = :ru
    I18n.t("hello").should eq("Привет")
    I18n.locale = :en
  end

  it "falls back to default_locale" do
    I18n.locale = :ru
    I18n.t("only_in_english").should eq("English only")
    I18n.locale = :en
  end

  it "pluralizes one/other with count" do
    I18n.t("inbox", count: 1).should eq("You have 1 message")
    I18n.t("inbox", count: 5).should eq("You have 5 messages")
  end

  it "available_locales from yml (String — Symbols не создаются в рантайме)" do
    I18n.available_locales.should contain("en")
    I18n.available_locales.should contain("ru")
  end

  it "localize formats time" do
    t = Time.utc(2026, 3, 15, 12, 30, 45)
    I18n.l(t, :db).should eq("2026-03-15 12:30:45")
  end

  it "localize formats TimeWithZone in its zone (:db → UTC)" do
    z = Time.utc(2026, 3, 15, 12, 30, 45).in_time_zone("Europe/Berlin")
    I18n.l(z, :db).should eq("2026-03-15 12:30:45")
    I18n.l(z).should eq("2026-03-15 13:30:45 +0100")
    I18n.localize(z, :short).should eq("15 Mar 13:30")
  end
end
