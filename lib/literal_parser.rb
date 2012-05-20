# encoding: utf-8



require 'literal_parser/version'
require 'strscan'
require 'bigdecimal'
require 'date'



# LiteralParser
#
# Parse Strings containing ruby literals.
#
# @example
#   LiteralParser.parse("nil") # => nil
#   LiteralParser.parse(":foo") # => :foo
#   LiteralParser.parse("123") # => 123
#   LiteralParser.parse("1.5") # => 1.5
#   LiteralParser.parse("1.5", use_big_decimal: true) # => #<BigDecimal:…,'0.15E1',18(18)>
#   LiteralParser.parse("[1, 2, 3]") # => [1, 2, 3]
#   LiteralParser.parse("{:a => 1, :b => 2}") # => {:a => 1, :b => 2}
#
# LiteralParser recognizes constants and the following literals:
#
#     nil                   # nil
#     true                  # true
#     false                 # false
#     -123                  # Fixnum/Bignum (decimal)
#     0b1011                # Fixnum/Bignum (binary)
#     0755                  # Fixnum/Bignum (octal)
#     0xff                  # Fixnum/Bignum (hexadecimal)
#     120.30                # Float (optional: BigDecimal)
#     1e0                   # Float
#     "foo"                 # String, no interpolation, but \t etc. work
#     'foo'                 # String, only \\ and \' are escaped
#     /foo/                 # Regexp
#     :foo                  # Symbol
#     :"foo"                # Symbol
#     2012-05-20            # Date
#     2012-05-20T18:29:52   # DateTime
#     [Any, Literals, Here] # Array
#     {Any => Literals}     # Hash
#
#
# @note Limitations
#
#   * LiteralParser does not support ruby 1.9's `{key: value}` syntax.
#   * LiteralParser does not currently support all of rubys escape sequences in strings
#     and symbols, e.g. "\C-…" type sequences don't work.
#   * Trailing commas in Array and Hash are not supported.
#
# @note BigDecimals
#
#   You can instruct LiteralParser to parse "12.5" as a bigdecimal and use "12.5e" to have
#   it parsed as float (short for "12.5e0", equivalent to "1.25e1")
#
# @note Date & Time
#
#   LiteralParser supports a subset of ISO-8601 for Date and Time which are not actual
#   valid ruby literals. The form YYYY-MM-DD (e.g. 2012-05-20) is translated to a Date
#   object, and YYYY-MM-DD"T"HH:MM:SS (e.g. 2012-05-20T18:29:52) is translated to a
#   Time object.
#
class LiteralParser

  # Raised when a String could not be parsed
  class SyntaxError < StandardError; end

  # @private
  # All the expressions used to parse the literals
  module Expressions

    RArrayBegin     = /\[/                                     # Match begin of an array

    RArrayVoid      = /\s*/                                    # Match whitespace between elements in an array

    RArraySeparator = /#{RArrayVoid},#{RArrayVoid}/            # Match the separator of array elements

    RArrayEnd       = /\]/                                     # Match end of an array

    RHashBegin      = /\{/                                     # Match begin of a hash

    RHashVoid       = /\s*/                                    # Match whitespace between elements in a hash

    RHashSeparator  = /#{RHashVoid},#{RHashVoid}/              # Match the separator of hash key/value pairs

    RHashArrow      = /#{RHashVoid}=>#{RHashVoid}/             # Match the separator between a key and a value in a hash

    RHashEnd        = /\}/                                     # Match end of a hash

    RConstant       = /[A-Z]\w*(?:::[A-Z]\w*)*/                # Match constant names (with nesting)

    RNil            = /nil/                                    # Match nil

    RFalse          = /false/                                  # Match false

    RTrue           = /true/                                   # Match true

    RInteger        = /[+-]?\d[\d_]*/                          # Match an Integer in decimal notation

    RBinaryInteger  = /[+-]?0b[01][01_]*/                      # Match an Integer in binary notation

    RHexInteger     = /[+-]?0x[A-Fa-f\d][A-Fa-f\d_]*/          # Match an Integer in hexadecimal notation

    ROctalInteger   = /[+-]?0[0-7][0-7'_,]*/                   # Match an Integer in octal notation

    RBigDecimal     = /#{RInteger}\.\d+/                       # Match a decimal number (Float or BigDecimal)

    RFloat          = /#{RBigDecimal}(?:f|e#{RInteger})/       # Match a decimal number in scientific notation

    RSString        = /'(?:[^\\']+|\\.)*'/                     # Match a single quoted string

    RDString        = /"(?:[^\\"]+|\\.)*"/                     # Match a double quoted string

    RRegexp         = %r{/((?:[^\\/]+|\\.)*)/([imxnNeEsSuU]*)} # Match a regular expression

    RSymbol         = /:\w+|:#{RSString}|:#{RDString}/         # Match a symbol

    RDate           = /(\d{4})-(\d{2})-(\d{2})/                # Match a date

    RTimeZone       = /(Z|[A-Z]{3,4}|[+-]\d{4})/               # Match a timezone

    RTime           = /(\d{2}):(\d{2}):(\d{2})(?:RTimeZone)?/  # Match a time (without date)

    RDateTime       = /#{RDate}T#{RTime}/                      # Match a datetime

    # Map escape sequences in double quoted strings
    DStringEscapes  = {
      '\\\\' => "\\",
      "\\'"  => "'",
      '\\"'  => '"',
      '\t'   => "\t",
      '\f'   => "\f",
      '\r'   => "\r",
      '\n'   => "\n",
    }
    256.times do |i|
      DStringEscapes["\\%o" % i]    = i.chr
      DStringEscapes["\\%03o" % i]  = i.chr
      DStringEscapes["\\x%02x" % i] = i.chr
      DStringEscapes["\\x%02X" % i] = i.chr
    end
  end
  include Expressions

  # Parse a String, returning the object which it contains.
  #
  # @example
  #     LiteralParser.parse(":foo") # => :foo
  #
  # @param [String] string
  #   The string which should be parsed
  # @param [nil, Hash] options
  #   An options-hash
  #
  # @option options [Boolean] :use_big_decimal
  #   Whether to use BigDecimal instead of Float for objects like "1.23".
  #   Defaults to false.
  # @option options [Boolean] :constant_base
  #   Determines from what constant other constants are searched.
  #   Defaults to Object (nil is treated as Object too, Object is the toplevel-namespace).
  #
  # @return [Object] The object in the string.
  #
  # @raise [LiteralParser::SyntaxError]
  #   If the String does not contain exactly one valid literal, a SyntaxError is raised.
  def self.parse(string, options=nil)
    parser  = new(string, options)
    value   = parser.scan_value
    raise SyntaxError, "Unexpected superfluous data: #{parser.rest.inspect}" unless parser.end_of_string?

    value
  end

  # @return [Module, nil]
  #   Where to lookup constants. Nil is toplevel (equivalent to Object).
  attr_reader :constant_base

  # @return [Boolean]
  #   True if "1.25" should be parsed into a big-decimal, false if it should be parsed as
  #   Float.
  attr_reader :use_big_decimal

  #
  # Parse a String, returning the object which it contains.
  #
  # @param [String] string
  #   The string which should be parsed
  # @param [nil, Hash] options
  #   An options-hash
  #
  # @option options [Boolean] :use_big_decimal
  #   Whether to use BigDecimal instead of Float for objects like "1.23".
  #   Defaults to false.
  # @option options [Boolean] :constant_base
  #   Determines from what constant other constants are searched.
  #   Defaults to Object (nil is treated as Object too, Object is the toplevel-namespace).
  def initialize(string, options=nil)
    options = options ? options.dup : {}
    @constant_base    = options[:constant_base] # nil means toplevel
    @use_big_decimal  = options.delete(:use_big_decimal) { false }
    @string           = string
    @scanner          = StringScanner.new(string)
  end

  # @return [Integer] The position of the scanner in the string
  def position
    @scanner.pos
  end

  # Moves the scanners position to the given character-index.
  #
  # @param [Integer] value
  #   The new position of the scanner
  def position=(value)
    @scanner.pos = value
  end

  # @return [Boolean] Whether the scanner reached the end of the string.
  def end_of_string?
    @scanner.eos?
  end

  # @return [String] The currently unprocessed rest of the string.
  def rest
    @scanner.rest
  end

  # Scans the string for a single value and advances the parsers position
  #
  # @return [Object] the scanned value
  #
  # @raise [LiteralParser::SyntaxError]
  #   When no valid ruby object could be scanned at the given position, a
  #   LiteralParser::SyntaxError is raised.
  def scan_value
    case
      when @scanner.scan(RArrayBegin)    then
        value = []
        @scanner.scan(RArrayVoid)
        if @scanner.scan(RArrayEnd)
          value
        else
          value << scan_value
          while @scanner.scan(RArraySeparator)
            value << scan_value
          end
          raise SyntaxError, "Expected ]" unless @scanner.scan(RArrayVoid) && @scanner.scan(RArrayEnd)

          value
        end
      when @scanner.scan(RHashBegin)    then
        value = {}
        @scanner.scan(RHashVoid)
        if @scanner.scan(RHashEnd)
          value
        else
          key = scan_value
          raise SyntaxError, "Expected =>" unless @scanner.scan(RHashArrow)
          val = scan_value
          value[key] = val
          while @scanner.scan(RHashSeparator)
            key = scan_value
            raise SyntaxError, "Expected =>" unless @scanner.scan(RHashArrow)
            val = scan_value
            value[key] = val
          end
          raise SyntaxError, "Expected }" unless @scanner.scan(RHashVoid) && @scanner.scan(RHashEnd)

          value
        end
      when @scanner.scan(RConstant)      then eval("#{@constant_base}::#{@scanner[0]}") # yes, I know it's evil, but it's sane due to the regex, also it's less annoying than deep_const_get
      when @scanner.scan(RNil)           then nil
      when @scanner.scan(RTrue)          then true
      when @scanner.scan(RFalse)         then false
      when @scanner.scan(RDateTime)      then
        Time.mktime(@scanner[1], @scanner[2], @scanner[3], @scanner[4], @scanner[5], @scanner[6])
      when @scanner.scan(RDate)          then
        date = @scanner[1].to_i, @scanner[2].to_i, @scanner[3].to_i
        Date.civil(*date)
      when @scanner.scan(RTime)          then
        now = Time.now
        Time.mktime(now.year, now.month, now.day, @scanner[1].to_i, @scanner[2].to_i, @scanner[3].to_i)
      when @scanner.scan(RFloat)         then Float(@scanner.matched.delete('^0-9.e-'))
      when @scanner.scan(RBigDecimal)    then
        data = @scanner.matched.delete('^0-9.-')
        @use_big_decimal ? BigDecimal(data) : Float(data)
      when @scanner.scan(ROctalInteger)  then Integer(@scanner.matched.delete('^0-9-'))
      when @scanner.scan(RHexInteger)    then Integer(@scanner.matched.delete('^xX0-9A-Fa-f-'))
      when @scanner.scan(RBinaryInteger) then Integer(@scanner.matched.delete('^bB01-'))
      when @scanner.scan(RInteger)       then @scanner.matched.delete('^0-9-').to_i
      when @scanner.scan(RRegexp)        then
        source = @scanner[1]
        flags  = 0
        lang   = nil
        if @scanner[2] then
          flags |= Regexp::IGNORECASE if @scanner[2].include?('i')
          flags |= Regexp::EXTENDED if @scanner[2].include?('m')
          flags |= Regexp::MULTILINE if @scanner[2].include?('x')
          lang   = @scanner[2].delete('^nNeEsSuU')[-1,1]
        end
        Regexp.new(source, flags, lang)
      when @scanner.scan(RSymbol)        then
        case @scanner.matched[1,1]
          when '"'
            @scanner.matched[2..-2].gsub(/\\(?:[0-3]?\d\d?|x[A-Fa-f\d]{2}|.)/) { |m|
              DStringEscapes[m]
            }.to_sym
          when "'"
            @scanner.matched[2..-2].gsub(/\\'/, "'").gsub(/\\\\/, "\\").to_sym
          else
            @scanner.matched[1..-1].to_sym
        end
      when @scanner.scan(RSString)       then
        @scanner.matched[1..-2].gsub(/\\'/, "'").gsub(/\\\\/, "\\")
      when @scanner.scan(RDString)       then
        @scanner.matched[1..-2].gsub(/\\(?:[0-3]?\d\d?|x[A-Fa-f\d]{2}|.)/) { |m| DStringEscapes[m] }
      else raise SyntaxError, "Unrecognized pattern: #{@scanner.rest.inspect}"
    end
  end
end
