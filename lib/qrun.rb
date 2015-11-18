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
      f_name = item.val.strip
      if $core_func.has_key? f_name
        apply_core_func(f_name, vm, ->(*x){qrun(*x)})
      elsif vm.bindings.has_key? f_name
        quote = vm.bindings[f_name]
        vm.program.unshift(*[quote.dup, QAtom.new('call')])
      else
        raise QuarkError, "No such function: #{f_name}"
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
