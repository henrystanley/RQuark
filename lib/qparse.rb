require 'parslet'
require 'qtypes'

## Parsing ##

class QuarkParse < Parslet::Parser
  rule(:integer) { match('[0-9]').repeat(1) }
  rule(:num) { (str("-").maybe >> integer >> (str('.') >> integer).maybe).as(:num) >> sep? } # Number
  rule(:atom) { match('[^0-9\[\]|:"\' \n\t]').repeat(1).as(:atom) >> sep? } # Function or Variable
  rule(:sym) { str(':') >> match('[^0-9\[\]|:"\' \n\t]').repeat(1).as(:sym) >> sep? } # Symbol
  rule(:stringA) { str("'") >> match("[^']").repeat(0).as(:string) >> str("'") }
  rule(:stringB) { str('"') >> match('[^"]').repeat(0).as(:string) >> str('"') }
  rule(:string) { (stringA | stringB) >> sep? } # String
  rule(:quote) {  # Quote
    str("[") >> sep? >>
    (qexpr >> sep? >> str("|") >> sep?).maybe.as(:pattern) >>
    qexpr.as(:body) >> sep? >> str("]") >> sep?
  }
  rule(:qexpr) { sep? >> ((num | atom | sym | string | quote)).repeat(0) }
  rule(:sep) { (match('\s') | match('\n') | match('\t')).repeat(1) }
  rule(:sep?) { sep.maybe }
  root :qexpr
end

class QuarkTransform < Parslet::Transform
  rule(:num => simple(:x)) { QNum.new(x.to_f) }
  rule(:atom => simple(:x)) { QAtom.new(x.to_s) }
  rule(:sym => simple(:x)) { QSym.new(x.to_s) }
  rule(:string => simple(:x)) { QStr.new(x.to_s) }
  rule(:string => sequence(:x)) { QStr.new('') }
  rule(:pattern => sequence(:a), :body => sequence(:b)) { QQuote.new(a, b) }
  rule(:pattern => simple(:a), :body => sequence(:b)) { QQuote.new([], b) }
  rule(:pattern => sequence(:a), :body => simple(:b)) { QQuote.new(a, []) }
  rule(:pattern => simple(:a), :body => simple(:b)) { QQuote.new([], []) }
end

def qparse str
  parsed = QuarkParse.new.parse(str)
  QuarkTransform.new.apply parsed
rescue Parslet::ParseFailed => e
  e.cause.ascii_tree
end
