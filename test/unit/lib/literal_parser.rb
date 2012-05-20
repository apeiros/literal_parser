# encoding: utf-8

require 'literal_parser'

suite "LiteralParser" do
  test "Parse nil" do
    assert_equal nil, LiteralParser.parse('nil')
  end
  test "Parse true" do
    assert_equal true, LiteralParser.parse('true')
  end
  test "Parse false" do
    assert_equal false, LiteralParser.parse('false')
  end
  test "Parse Integers" do
    assert_equal 123, LiteralParser.parse('123')
    assert_equal -123, LiteralParser.parse('-123')
    assert_equal 1_234_567, LiteralParser.parse('1_234_567')
    assert_equal 0b1011, LiteralParser.parse('0b1011')
    assert_equal 0xe3, LiteralParser.parse('0xe3')
  end
  test "Parse Floats" do
    assert_equal 12.37, LiteralParser.parse('12.37')
    assert_equal -31.59, LiteralParser.parse('-31.59')
    assert_equal 1.2e5, LiteralParser.parse('1.2e5')
    assert_equal 1.2e-5, LiteralParser.parse('1.2e-5')
    assert_equal -1.2e5, LiteralParser.parse('-1.2e5')
    assert_equal -1.2e-5, LiteralParser.parse('-1.2e-5')
  end
  test "Parse BigDecimals" do
    assert_equal BigDecimal("12.37"), LiteralParser.parse('12.37', use_big_decimal: true)
  end
  test "Parse Symbols" do
    assert_equal :simple_symbol, LiteralParser.parse(':simple_symbol')
    assert_equal :"double quoted symbol", LiteralParser.parse(':"double quoted symbol"')
    assert_equal :'single quoted symbol', LiteralParser.parse(":'single quoted symbol'")
  end
  test "Parse Strings" do
    assert_equal 'Single Quoted String', LiteralParser.parse(%q{'Single Quoted String'})
    assert_equal "Double Quoted String", LiteralParser.parse(%q{"Double Quoted String"})
    assert_equal 'Single Quoted String \t\n\r\'\"', LiteralParser.parse(%q{'Single Quoted String \t\n\r\'\"'})
    assert_equal "Double Quoted String \t\n\r\'\"", LiteralParser.parse(%q{"Double Quoted String \t\n\r\'\""})
  end
  test "Parse Regexes" do
    assert_equal /some_regex/, LiteralParser.parse('/some_regex/')
    assert_equal /some_regex/imx, LiteralParser.parse('/some_regex/imx')
  end
  test "Parse Date" do
    assert_equal Date.civil(2012,5,20), LiteralParser.parse('2012-05-20')
  end
  test "Parse Time" do
    assert_equal Time.mktime(2012,5,20,18,29,52), LiteralParser.parse('2012-05-20T18:29:52')
  end
  test "Parse Array" do
    array_string    = '[nil, false, true, 123, 12.5, 2012-05-20, :sym, "str"]'
    expected_array  = [nil, false, true, 123, 12.5, Date.civil(2012,5,20), :sym, "str"]
    assert_equal expected_array, LiteralParser.parse(array_string)
  end
  test "Parse Hash" do
    array_string    = '{nil => false, true => 123, 12.5 => 2012-05-20, :sym => "str"}'
    expected_array  = {nil => false, true => 123, 12.5 => Date.civil(2012,5,20), :sym => "str"}
    assert_equal expected_array, LiteralParser.parse(array_string)
  end
  test "Parse Constants" do
    assert_equal Time, LiteralParser.parse('Time')
  end
  test "Perform manual parsing" do
    parser = LiteralParser.new("'hello'\n12\ntrue")
    assert_equal 0, parser.position
    assert_equal 'hello', parser.scan_value
    assert_equal "\n12\ntrue", parser.rest
    assert_equal 7, parser.position
    assert_equal false, parser.end_of_string?

    parser.position += 1
    assert_equal 8, parser.position
    assert_equal 12, parser.scan_value
    assert_equal "\ntrue", parser.rest
    assert_equal 10, parser.position
    assert_equal false, parser.end_of_string?

    parser.position += 1
    assert_equal 11, parser.position
    assert_equal true, parser.scan_value
    assert_equal "", parser.rest
    assert_equal 15, parser.position
    assert_equal true, parser.end_of_string?
  end
end
