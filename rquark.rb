require_relative 'qtypes'
require_relative 'qparse'
require_relative 'qeval'

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

def qrepl
  vm = QVM.new([], [], {})
  loop do
    print ':> '
    begin
      input = $stdin.gets.chomp
      case input.strip
      when '*q'
        exit!
      when '*b'
        vm.bindings.each { |k, v| puts "#{k} = #{v.to_s}"}
      else
        vm = qrun(input, vm.stack.dup, vm.bindings.dup)
      end
    rescue Exception => e
      puts e
    end
  end
end

qrepl
