# ActiveSupport::NumberHelper — port of Rails number formatting
# (number_to_currency, number_to_delimited, ...), values verified
# against oracle/expected.yml (activesupport 8.1.4).

module ActiveSupport
  module NumberHelper
    extend self

    STORAGE_UNITS = [{:eb, 1024_i64**6}, {:pb, 1024_i64**5}, {:tb, 1024_i64**4},
                     {:gb, 1024_i64**3}, {:mb, 1024_i64**2}, {:kb, 1024_i64}, {:byte, 1_i64}]

    DECIMAL_UNITS = [{:quadrillion, 15_i64}, {:trillion, 12_i64}, {:billion, 9_i64},
                     {:million, 6_i64}, {:thousand, 3_i64}]

    # --- number_to_delimited / number_with_delimiter ----------------------

    def number_to_delimited(number : Int | Float, delimiter : String = ",",
                            separator : String = ".", pattern : Regex = /(\d)(?=(\d{3})+$)/) : String
      int, frac = delimited_parts(number, separator)
      grouped = int.gsub(pattern) do |match|
        "#{match}#{delimiter}"
      end
      frac ? "#{grouped}#{separator}#{frac}" : grouped
    end

    def number_with_delimited(number : Int | Float, **options) : String
      number_to_delimited(number, **options)
    end

    # --- number_to_rounded / number_with_precision -------------------------

    def number_to_rounded(number : Int | Float, precision : Int32 = 3,
                          significant : Bool = false, separator : String = ".",
                          strip_insignificant_zeros : Bool = false) : String
      rounded =
        if significant
          digits = precision - (number.abs >= 1 ? Math.log10(number.abs).floor.to_i + 1 : 1)
          digits = {digits, 0}.max
          if number.abs >= 1 && digits < 0
            "%.0f" % number.to_f.round(digits: precision - 1, base: 10, mode: :ties_away)
          else
            sprintf("%.#{digits}f", number)
          end
        else
          sprintf("%.#{precision}f", number)
        end
      rounded = rounded.sub(/(\.\d*?)0+\z/, "\\1").sub(/\.\z/, "") if strip_insignificant_zeros
      rounded
    end

    def number_with_precision(number : Int | Float, **options) : String
      number_to_rounded(number, **options)
    end

    # --- number_to_currency --------------------------------------------------

    def number_to_currency(number : Int | Float, precision : Int32 = 2, unit : String = "$",
                           format : String = "%u%n", negative_format : String = "-%u%n",
                           separator : String = ".", delimiter : String = ",") : String
      number = number.to_f
      template = number < 0 ? negative_format : format
      formatted = number_to_rounded(number.abs, precision: precision,
        separator: separator, strip_insignificant_zeros: false)
      digits = delimited_digits(formatted, delimiter, separator)
      template.gsub("%n", digits).gsub("%u", unit)
    end

    # --- number_to_percentage --------------------------------------------------

    def number_to_percentage(number : Int | Float, precision : Int32 = 3,
                             separator : String = ".", delimiter : String = "") : String
      formatted = number_to_rounded(number, precision: precision,
        separator: separator, strip_insignificant_zeros: false)
      "#{formatted}%"
    end

    # --- number_to_human_size ---------------------------------------------------

    def number_to_human_size(number : Int | Float, precision : Int32 = 3,
                             significant : Bool = true, separator : String = ".",
                             delimiter : String = "", strip_insignificant_zeros : Bool = true) : String
      size = number.to_f.abs
      unit_value = 1_i64
      unit = :byte
      STORAGE_UNITS.each do |name, value|
        if size >= value
          unit = name
          unit_value = value
          break
        end
      end
      if unit == :byte
        rendered = number.to_i.abs.to_s
        stripped = strip_zeros(rendered, strip_insignificant_zeros)
        return "#{number < 0 ? "-" : ""}#{stripped} Bytes"
      end
      scaled = size / unit_value
      "#{sign_prefix(number)}#{significant_rounded(scaled, precision, separator, strip_insignificant_zeros)} #{unit_label(unit, scaled)}"
    end

    # --- number_to_human -----------------------------------------------------------

    def number_to_human(number : Int | Float, precision : Int32 = 3,
                        significant : Bool = true, separator : String = ".",
                        delimiter : String = "", strip_insignificant_zeros : Bool = true) : String
      value = number.to_f.abs
      unit_exponent = 0_i64
      DECIMAL_UNITS.each do |name, exponent|
        if value >= 10_i64**exponent
          unit_exponent = exponent
          break
        end
      end
      if unit_exponent.zero?
        rendered = number.to_i.abs.to_s
        return "#{number < 0 ? "-" : ""}#{rendered}"
      end
      scaled = value / (10_i64**unit_exponent)
      label = DECIMAL_UNITS.find { |_, exp| exp == unit_exponent }.not_nil![0].to_s.capitalize
      "#{sign_prefix(number)}#{significant_rounded(scaled, precision, separator, strip_insignificant_zeros)} #{label}"
    end

    # --- number_to_phone ----------------------------------------------------------

    def number_to_phone(number : Int | String, area_code : Bool = false, delimiter : String = "-",
                        extension : String? = nil, country_code : String? = nil) : String
      digits = number.to_s.delete("^0-9")
      raise ArgumentError.new("number must have 10 digits") unless digits.size == 10
      formatted = area_code ? "(#{digits[0, 3]}) #{digits[3, 3]}#{delimiter}#{digits[6, 4]}" :
        "#{digits[0, 3]}#{delimiter}#{digits[3, 3]}#{delimiter}#{digits[6, 4]}"
      formatted = "#{country_code}#{delimiter}#{formatted}" if country_code
      formatted = "#{formatted} x #{extension}" if extension
      formatted
    end

    # --- internals ---------------------------------------------------------------

    private def delimited_parts(number : Int | Float, separator : String) : {String, String?}
      text = number.to_s
      if text.includes?('.')
        int, frac = text.split('.', 2)
        {int, frac}
      elsif text.includes?('e')
        text = "%.10f" % number.to_f
        int, frac = text.split('.', 2)
        frac = frac.sub(/0+\z/, "")
        frac.empty? ? {int, nil} : {int, frac}
      else
        {text, nil}
      end
    end

    private def delimited_digits(formatted : String, delimiter : String, separator : String) : String
      int, frac = formatted.includes?('.') ? formatted.split('.', 2) : {formatted, nil}
      grouped = int.gsub(/(\d)(?=(\d{3})+$)/) { |m| "#{m}#{delimiter}" }
      frac ? "#{grouped}#{separator}#{frac}" : grouped
    end

    private def significant_rounded(value : Float64, precision : Int32,
                                    separator : String, strip : Bool) : String
      digits = precision - (value >= 1 ? Math.log10(value).floor.to_i + 1 : 1)
      digits = {digits, 0}.max
      rendered = sprintf("%.#{digits}f", value)
      strip_zeros(rendered, strip).sub(".", separator)
    end

    private def strip_zeros(rendered : String, strip : Bool) : String
      return rendered unless strip
      rendered.sub(/(\.\d*?)0+\z/, "\\1").sub(/\.\z/, "")
    end

    private def sign_prefix(number : Int | Float) : String
      number.to_f < 0 ? "-" : ""
    end

    private def unit_label(unit : Symbol, scaled : Float64) : String
      case unit
      when :byte then scaled == 1 ? "Byte" : "Bytes"
      else            unit.to_s.upcase
      end
    end
  end
end
