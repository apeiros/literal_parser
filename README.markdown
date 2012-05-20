README
======


Summary
-------
Parse Strings containing ruby literals and return a proper ruby object.


Features
--------

* Recognizes about all Ruby literals: nil, true, false, Symbols, Integers, Floats, Hashes,
  Arrays
* Additionally parses Constants, Dates and Times
* Very easy to use


Installation
------------
`gem install literal_parser`


Usage
-----

A couple of examples:

    LiteralParser.parse("nil") # => nil
    LiteralParser.parse(":foo") # => :foo
    LiteralParser.parse("123") # => 123
    LiteralParser.parse("1.5") # => 1.5
    LiteralParser.parse("1.5", use_big_decimal: true) # => #<BigDecimal:…,'0.15E1',18(18)>
    LiteralParser.parse("[1, 2, 3]") # => [1, 2, 3]
    LiteralParser.parse("{:a => 1, :b => 2}") # => {:a => 1, :b => 2}




Links
-----

* [Online API Documentation](http://rdoc.info/github/apeiros/literal_parser/)
* [Public Repository](https://github.com/apeiros/literal_parser)
* [Bug Reporting](https://github.com/apeiros/literal_parser/issues)
* [RubyGems Site](https://rubygems.org/gems/literal_parser)


License
-------

You can use this code under the {file:LICENSE.txt BSD-2-Clause License}, free of charge.
If you need a different license, please ask the author.
