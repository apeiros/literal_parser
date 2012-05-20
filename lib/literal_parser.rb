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
#
# @note Hashes and 1.9 Syntax
#   LiteralParser does not support ruby 1.9's {key: value} syntax.
#
# @note BigDecimals
#   You can instruct LiteralParser to parse "12.5" as a bigdecimal and use "12.5e" to have
#   it parsed as float (short for "12.5e0", equivalent to "1.25e1")
#
# @note Strings & Symbols
#   LiteralParser does not currently support all of rubys escape sequences in strings,
#   e.g. "\C-…" type sequences don't work.
#
# @note Date & Time
#   LiteralParser supports a subset of ISO-8601 for Date and Time which are not actual
#   valid ruby literals. The form YYYY-MM-DD (e.g. 2012-05-20) is translated to a Date
#   object, and YYYY-MM-DD"T" (e.g. 2012-05-20T18:29:52) is translated to a Time object.
#
# LiteralParser recognizes constants and the following literals:
#   nil                   # nil
#   true                  # true
#   false                 # false
#   -123                  # Fixnum/Bignum (decimal)
#   0b1011                # Fixnum/Bignum (binary)
#   0755                  # Fixnum/Bignum (octal)
#   0xff                  # Fixnum/Bignum (hexadecimal)
#   120.30                # Float (optional: BigDecimal)
#   1e0                   # Float
#   "foo"                 # String, no interpolation, but \t etc. work
#   'foo'                 # String, only \\ and \' are escaped
#   /foo/                 # Regexp
#   :foo                  # Symbol
#   :"foo"                # Symbol
#   2012-05-20            # Date
#   2012-05-20T18:29:52   # DateTime
#   [Any, Literals, Here] # Array
#   {Any => Literals}     # Hash
#
# TODO
# * ruby with 32bit and version < 1.9.2 raises RangeError for too big/small Time
#   instances, should we degrade to DateTime for those?
# * Implement %-literals (String: %, %Q, %q, Symbol: %s; Regexp: %r; Array: %W, %w)
# * Complete escape sequences in strings.
class LiteralParser
  RArrayBegin     = /\[/
  RArrayVoid      = /\s*/
  RArraySeparator = /#{RArrayVoid},#{RArrayVoid}/
  RArrayEnd       = /\]/
  RHashBegin      = /\{/
  RHashVoid       = /\s*/
  RHashSeparator  = /#{RHashVoid},#{RHashVoid}/
  RHashArrow      = /#{RHashVoid}=>#{RHashVoid}/
  RHashEnd        = /\}/
  RConstant       = /[A-Z]\w*(?:::[A-Z]\w*)*/
  RNil            = /nil/
  RFalse          = /false/
  RTrue           = /true/
  RInteger        = /[+-]?\d[\d_]*/
  RBinaryInteger  = /[+-]?0b[01][01_]*/
  RHexInteger     = /[+-]?0x[A-Fa-f\d][A-Fa-f\d_]*/
  ROctalInteger   = /[+-]?0[0-7][0-7'_,]*/
  RBigDecimal     = /#{RInteger}\.\d+/
  RFloat          = /#{RBigDecimal}(?:f|e#{RInteger})/
  RSString        = /'(?:[^\\']+|\\.)*'/
  RDString        = /"(?:[^\\"]+|\\.)*"/
  RRegexp         = %r{/((?:[^\\/]+|\\.)*)/([imxnNeEsSuU]*)}
  RSymbol         = /:\w+|:#{RSString}|:#{RDString}/
  RDate           = /(\d{4})-(\d{2})-(\d{2})/
  RTimeZone       = /(Z|[A-Z]{3,4}|[+-]\d{4})/
  RTime           = /(\d{2}):(\d{2}):(\d{2})(?:RTimeZone)?/
  RDateTime       = /#{RDate}T#{RTime}/
  RSeparator      = /[^A-Z\#nft\d:'"\/+-]+|$/
  RTerminator     = /\s*(?:\#.*)?(?:\n|\r\n?|\Z)/

  RIdentifier     = /[A-Za-z_]\w*/

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

  def self.parse(string, opt=nil)
    new(string, opt).value
  end

  attr_reader :value
  attr_reader :constant_base
  attr_reader :use_big_decimal

  def initialize(string, opt=nil)
    opt = opt ? opt.dup : {}
    @constant_base    = opt[:constant_base] # nil means toplevel
    @use_big_decimal  = opt.delete(:use_big_decimal) { false }
    @string           = string
    @scanner          = StringScanner.new(string)
    @value            = scan_value
    raise SyntaxError, "Unexpected superfluous data: #{@scanner.rest.inspect}" unless @scanner.eos?
  end

private
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
