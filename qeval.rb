require_relative 'qtypes'

## Boilerplate ##

QuarkError = Class.new(RuntimeError)

$core_func = {}
$core_func_type = {}

def def_cf(name, type_sig, &code)
  $core_func_type[name] = type_sig
  $core_func[name] = code
end

def apply_core_func(name, vm, eval_func)
  eq, expected, got = type_check(vm.stack, $core_func_type[name])
  raise(QuarkError, "Type error with function #{name}\n  expected a stack of #{expected}\n  but got #{got}") if not eq
  $core_func[name].call(vm, eval_func)
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


## Quark Core Functions ##

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

def_cf('>>', [:Quote]) do |vm|
  vm.stack.push vm.stack.last.pop
end

def_cf('<<', [:Quote, :Any]) do |vm|
  vm.stack[-2].push vm.stack.pop
end

def_cf('@>', [:Quote]) do |vm|
  vm.stack.push vm.stack.last.pattern.pop
end

def_cf('<@', [:Quote, :Any]) do |vm|
  vm.stack[-2].pattern.push vm.stack.pop
end

def_cf('show', [:Any]) do |vm|
  vm.stack.push QStr.new(vm.stack.pop.to_s)
end

def_cf('call', [:Quote]) do |vm|
  quote = vm.stack.pop
  args = vm.stack.pop(quote.pattern.length)
  if bindings=pattern_match(args, quote.pattern)
    vm.program.unshift(*quote.bind(bindings).body)
  else vm.stack.push QSym.new('nil') end
end

def_cf('match', [:Quote]) do |vm|
  quotes = vm.stack.pop.body
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

def_cf('def', [:Quote, :Sym]) do |vm|
  name = vm.stack.pop.val
  quote = vm.stack.pop
  vm.bindings[name] = quote
end

def_cf('eval', [:Str]) do |vm, eval_func|
  begin
    eval_str = vm.stack.pop.val
    vm2 = eval_func.call(eval_str, vm.stack.dup, vm.bindings.dup)
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
