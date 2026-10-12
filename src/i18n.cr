# I18n — minimal Rails-compatible t/translate on YAML backends.
#
#   I18n.load_path << "config/locales/en.yml"
#   I18n.t("greeting", name: "Ada")          # interpolation %{name}
#   I18n.t("missing", default: "fallback")
#   I18n.t("inbox", count: 1)                # one/other pluralization
#
# YAML shape (flat keys "en.greeting", Rails-convention dotted):

require "yaml"

module I18n
  class MissingTranslation < Exception
    def initialize(key : String, locale : Symbol)
      super("translation missing: #{locale}.#{key}")
    end
  end

  @@load_path = [] of String
  @@locale : Symbol = :en
  @@default_locale : Symbol = :en
  # Locale keys stored as String: Crystal cannot mint Symbols at runtime
  # (YAML locale names arrive as strings).
  @@translations = {} of String => Hash(String, String)

  def self.load_path : Array(String)
    @@load_path
  end

  def self.load_path=(paths : Array(String))
    @@load_path = paths
    reload!
  end

  def self.reload! : Nil
    @@translations.clear
    @@load_path.each do |file|
      next unless File.exists?(file)
      data = YAML.parse(File.read(file)).as_h?
      next unless data
      data.each do |locale_str, tree|
        locale = locale_str.to_s
        flat = @@translations[locale] ||= {} of String => String
        flatten("", tree, flat)
      end
    end

    # Keys inside a locale table do NOT carry the locale prefix:
    # en: { nav: { dashboard: ... } } → "nav.dashboard".
  end

  def self.locale : Symbol
    @@locale
  end

  def self.locale=(locale : Symbol) : Symbol
    @@locale = locale
  end

  def self.default_locale : Symbol
    @@default_locale
  end

  def self.default_locale=(locale : Symbol) : Symbol
    @@default_locale = locale
  end

  def self.available_locales : Array(String)
    load_if_needed
    @@translations.keys
  end

  # t("a.b.c", default: "...", count: n, **interp)
  def self.t(key : String, default : String? = nil, count : Int32? = nil, **interpolations) : String
    load_if_needed
    resolved = lookup(key) || lookup(key, @@default_locale)
    if resolved.nil? && count
      resolved = lookup(plural_key(key, count)) || lookup(plural_key(key, count), @@default_locale)
    end
    resolved = resolved || default
    raise MissingTranslation.new(key, @@locale) unless resolved
    if count
      result = interpolate(resolved, **interpolations)
      result.gsub("%{count}", count.to_s)
    else
      interpolate(resolved, **interpolations)
    end
  end

  def self.translate(key : String, **options) : String
    t(key, **options)
  end

  def self.l(time : Time, format : Symbol = :default) : String
    time.to_fs(format)
  end

  def self.localize(time : Time, format : Symbol = :default) : String
    l(time, format)
  end

  # TimeWithZone: format in the zone's wall clock (zoned fields, and
  # :db renders UTC like Rails' TimeWithZone#to_fs).
  def self.l(time : ActiveSupport::TimeWithZone, format : Symbol = :default) : String
    time.to_fs(format)
  end

  def self.localize(time : ActiveSupport::TimeWithZone, format : Symbol = :default) : String
    l(time, format)
  end

  # --- internals ------------------------------------------------------

  def self.lookup(key : String, locale : Symbol = @@locale) : String?
    load_if_needed
    table = @@translations[locale.to_s]?
    table.try &.[key]?
  end

  private def self.load_if_needed
    reload! if @@translations.empty? && !@@load_path.empty?
  end

  private def self.plural_key(key : String, count : Int32) : String
    "#{key}.#{count == 1 ? "one" : "other"}"
  end

  private def self.interpolate(template : String, **vars) : String
    result = template
    vars.each do |key, value|
      result = result.gsub("%{#{key}}", value.to_s)
    end
    result
  end

  private def self.flatten(prefix : String, node : YAML::Any, into : Hash(String, String)) : Nil
    if hash = node.as_h?
      hash.each do |k, v|
        flatten(prefix.empty? ? k.to_s : "#{prefix}.#{k}", v, into)
      end
    elsif node.as_s?
      into[prefix] = node.as_s
    end
  end
end
