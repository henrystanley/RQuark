require 'parslet'

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
rescue Parslet::ParseFailed => failure
  puts failure.cause.ascii_tree
end

## Quark Values ##

class QVal
  attr_accessor :val
  def initialize(v)
    @val = v
  end
  def to_s
    @val.to_s
  end
  def ==(a)
    return @val == a.val if a.is_a? self.class
    false
  end
end

class QNum < QVal
  def qtype; :Num end
end

class QAtom < QVal
  def qtype; :Atom end
end

class QSym < QVal
  def to_s
    ":#{@val.to_s}"
  end
  def qtype; :Sym end
end

class QStr < QVal
  def to_s
    "\"#{@val.to_s}\""
  end
  def qtype; :Str end
end

class QQuote
  attr_accessor :pattern, :body
  def initialize(p, b)
    @pattern = p
    @body = b
  end
  def push x
    @body.push x
  end
  def pop
    @body.pop
  end
  def to_s
    return "[ #{@body.join(' ')} ]" if @pattern.empty?
    "[ #{@pattern.join(' ')} | #{@body.join(' ')} ]"
  end
  def qtype
    pattern_type = @pattern.map { |i| i.qtype }.inject { |x, y| x == y ? x : :any } || :Empty
    body_type = @body.map { |i| i.qtype }.inject { |x, y| x == y ? x : :any } || :Empty
    [:Quote, pattern_type, body_type]
  end
  def bind(bindings)
    bindings.each do |k, v|
      @body.map! do |x|
        if x.is_a? QQuote then x.bind({k => v})
        elsif x.is_a? QAtom then x.val == k ? v : x
        else x end
      end
    end
    return self
  end
end

## Type Checking ##

# type comparison is not symmetric
# `a` is the signature type, so [:Any, :Empty] will match, but [:Empty, :Any] won't
def type_match(a, b)
  return true if (a == :Any)
  return true if (a == :NotEmpty) && (b != :Empty)
  if (a.is_a? Array) && (b.is_a? Array) && (a[0] == :Quote) && (b[0] == :Quote)
    return (type_match(a[1], b[1]) && type_match(a[2], b[2]))
  end
  a == b
end

def type_check(stack, type_sig)
  return false if stack.length < type_sig.length
  return true if type_sig.length == 0
  stack_type = stack[-(type_sig.length)..-1].map(&:qtype)
  types_eq = type_sig.zip(stack_type)
    .map { |sig, type| type_match(sig, type) }
    .inject(true) { |a, b| a && b}
  return types_eq, type_sig, stack_type
end

def type_to_qitem(t)
  return QSym.new(t.to_s) if t.is_a? Symbol
  QQuote.new([], t.map { |x| type_to_qitem x })
end

## Quark Core Functions ##

# boilerplate

QuarkError = Class.new(RuntimeError)

$core_func = {}
$core_func_type = {}

def def_cf(name, type_sig, &code)
  $core_func_type[name] = type_sig
  $core_func[name] = code
end

def apply_core_func(name, vm)
  eq, expected, got = type_check(vm.stack, $core_func_type[name])
  raise(QuarkError, "Type error with function #{name}\n  expected a stack of #{expected}\n  but got #{got}") if not eq
  $core_func[name].call(vm)
end

def apply_runtime_func(name, vm)
  quote = vm.bindings[name]
  vm.program.unshift(*[quote, QAtom.new('call')])
end

def pattern_match(stack_args, args)
  return false if stack_args.length < args.length
  return {} if args.length == 0
  bindings = {}
  args.zip(stack_args).each do |a, s|
    if a.is_a? QAtom
      return false if (bindings.has_key? a.val) && (bindings[a.val] != s)
      bindings[a.val] = s
    else
      return false if a != s
    end
  end
  return bindings
end

def deep_clone x
  Marshal.load(Marshal.dump(x))
end

# actual functions

def_cf('+', [:Num, :Num]) do |vm|
  vm.stack.push QNum.new(vm.stack.pop.val + vm.stack.pop.val)
end

def_cf('*', [:Num, :Num]) do |vm|
  vm.stack.push QNum.new(vm.stack.pop.val * vm.stack.pop.val)
end

def_cf('/', [:Num, :Num]) do |vm|
  vm.stack.push QNum.new(vm.stack.pop.val / vm.stack.pop.val)
end

def_cf('<', [:Num, :Num]) do |vm|
  smaller_than = vm.stack.pop.val > vm.stack.pop.val
  vm.stack.push QSym.new(smaller_than ? 'true' : 'nil')
end

def_cf('print', [:Str]) do |vm|
  print vm.stack.pop.val
end

def_cf('.', []) do |vm|
  puts vm.stack.join(' ')
end

def_cf('>>', [[:Quote, :Any, :NotEmpty]]) do |vm|
  vm.stack.push vm.stack.last.pop
end

def_cf('<<', [[:Quote, :Any, :Any], :Any]) do |vm|
  vm.stack[-2].push vm.stack.pop
end

def_cf('@>', [[:Quote, :NotEmpty, :Any]]) do |vm|
  vm.stack.push vm.stack.last.pattern.pop
end

def_cf('<@', [[:Quote, :Any, :Any], :Any]) do |vm|
  vm.stack[-2].pattern.push vm.stack.pop
end

def_cf('show', [:Any]) do |vm|
  vm.stack.push QStr.new(vm.stack.pop.to_s)
end

def_cf('call', [[:Quote, :Any, :Any]]) do |vm|
  quote = vm.stack.pop
  args = vm.stack.pop(quote.pattern.length)
  if bindings=pattern_match(args, quote.pattern)
    vm.program.unshift(*quote.bind(bindings).body)
  else vm.stack.push QSym.new('nil') end
end

def_cf('match', [[:Quote, :Empty, [:Quote, :Any, :Any]]]) do |vm|
  quotes = vm.stack.pop.body.reverse
  quotes.each do |q|
    if bindings=pattern_match(vm.stack.last(q.pattern.length), q.pattern)
      vm.stack.pop(q.pattern.length)
      vm.program.unshift(*q.bind(bindings).body)
      break
    end
  end
end

def_cf('chars', [:Str]) do |vm|
  chars = vm.stack.pop.val.chars.map { |c| QStr.new c }
  vm.stack.push QQuote.new([], chars)
end

def_cf('weld', [:Str, :Str]) do |vm|
  string_a = vm.stack.pop.val
  string_b = vm.stack.pop.val
  vm.stack.push QStr.new(string_b + string_a)
end

def_cf('def', [[:Quote, :Any, :Any], :Sym]) do |vm|
  name = vm.stack.pop.val
  quote = vm.stack.pop
  vm.bindings[name] = quote
end

def_cf('eval', [:Str]) do |vm|
  begin
    eval_prog = qparse(vm.stack.pop.val)
    vm2 = qeval QVM.new(deep_clone(vm.stack), eval_prog, deep_clone(vm.bindings))
    vm.stack, vm.bindings = vm2.stack, vm2.bindings
    vm.stack.push QSym.new('ok')
  rescue
    vm.stack.push QSym.new('not-ok')
  end
end

def_cf('type', [:Any]) do |vm|
  type = type_to_qitem vm.stack.pop.qtype
  vm.stack.push type
end

def_cf('load', [:Str]) do |vm|
  vm.stack.push QStr.new(File.read(vm.stack.pop.val))
end

def_cf('cmd', [:Str]) do |vm|
  vm.stack.push QStr.new(IO.popen(vm.stack.pop.val).read)
end

def_cf('write', [:Str, :Str]) do |vm|
  filename, content = vm.stack.pop.val, vm.stack.pop.val
  File.open(filename, 'w+') { |f| f << content }
end

def_cf('exit', []) do |vm|
  exit
end


## Evaluation ##

QVM = Struct.new(:stack, :program, :bindings)

def qeval vm
  until vm.program.empty?
    item = vm.program.shift
    if item.is_a? QAtom
      if $core_func.has_key? item.val
        apply_core_func(item.val, vm)
      elsif vm.bindings.has_key? item.val
        apply_runtime_func(item.val, vm)
      else
        raise QuarkError, "No such function: #{item}"
      end
    else
      vm.stack.push item
    end
  end
  return vm
end

def qrepl
  vm = QVM.new([], [], {})
  loop do
    vm2 = Marshal.load(Marshal.dump(vm))
    print ':> '
    begin
      input = $stdin.gets.chomp
      exit! if input == '*q'
      vm2.program = qparse input
      qeval(vm2)
    rescue Exception => e
      puts e
    end
    vm = vm2
  end
end

qrepl
