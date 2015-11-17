require 'qtypes'
require 'qparse'
require 'qeval'

## Evaluation ##

QVM = Struct.new(:stack, :program, :bindings)

def qrun(str, stack=[], bindings={})
  qreduce QVM.new(stack, qparse(str), bindings)
end

def qreduce vm
  until vm.program.empty?
    item = vm.program.shift
    if item.is_a? QAtom
      if $core_func.has_key? item.val
        apply_core_func(item.val, vm, ->(*x){qrun(*x)})
      elsif vm.bindings.has_key? item.val
        quote = vm.bindings[item.val]
        vm.program.unshift(*[quote.dup, QAtom.new('call')])
      else
        raise QuarkError, "No such function: #{item}"
      end
    else
      vm.stack.push item
    end
  end
  return vm
end

def qrepl(vm)
  loop do
    print ':> '
    begin
      input = $stdin.gets.chomp
      case input.strip
      when '*q'
        exit!
      when '*f'
        vm.bindings.sort.each { |k, v| puts "#{k}\n    #{v.to_s}\n\n"}
      when /\*f\s+(.+)/
        if vm.bindings.has_key? $1
          puts vm.bindings[$1]
        else puts "No such function: #{$1}" end
      else
        vm = qrun(input, vm.stack.dup, vm.bindings.dup)
      end
      puts vm.stack.map { |x| x.is_a?(QQuote) ? x.to_s(20) : x.to_s }.join(' ')
    rescue Exception => e
      puts e
    end
  end
end
