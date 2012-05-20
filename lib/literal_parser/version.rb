# encoding: utf-8

begin
  require 'rubygems/version' # newer rubygems use this
rescue LoadError
  require 'gem/version' # older rubygems use this
end

class LiteralParser

  # The version of the LiteralParser library
  Version = Gem::Version.new("1.0.0")
end
