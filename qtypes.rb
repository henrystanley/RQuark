
## Quark Values ##

# parent class for all the quark primitive values
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

# quark numbers
class QNum < QVal
  def qtype; :Num end
end

# quark functions/variables
class QAtom < QVal
  def qtype; :Atom end
end

# quark symbols
class QSym < QVal

  def to_s
    ":#{@val.to_s}"
  end

  def qtype; :Sym end
end

# quark strings
class QStr < QVal

  def to_s
    "\"#{@val.to_s}\""
  end

  def qtype; :Str end
end

# class for quark quotes
class QQuote

  attr_accessor :pattern, :body

  def initialize(p, b)
    @pattern = p
    @body = b
  end

  def to_s
    return "[ #{@body.join(' ')} ]" if @pattern.empty?
    "[ #{@pattern.join(' ')} | #{@body.join(' ')} ]"
  end

  def dup
    Marshal.load(Marshal.dump(self))
  end

  def qtype
    pattern_type = @pattern.map { |i| i.qtype }.inject { |x, y| x == y ? x : :any } || :Empty
    body_type = @body.map { |i| i.qtype }.inject { |x, y| x == y ? x : :any } || :Empty
    [:Quote, pattern_type, body_type]
  end

  # pushes to quote body
  def push x
    @body.push x
  end

  # pops from quark body
  def pop
    @body.pop
  end

  # takes a hash of var strings to quark items and recursively subs its body
  def bind bindings
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

# compares two qtype to see if they are equivelent
# type comparison is not symmetric
# `a` is the signature type, so (:Any, :Empty) will match, but (:Empty, :Any) won't
def type_match(a, b)
  return true if (a == :Any)
  return true if (a == :NotEmpty) && (b != :Empty)
  if (a.is_a? Array) && (b.is_a? Array) && (a[0] == :Quote) && (b[0] == :Quote)
    return (type_match(a[1], b[1]) && type_match(a[2], b[2]))
  end
  a == b
end

# matches a type signature against a data stack
def type_check(stack, type_sig)
  return false if stack.length < type_sig.length
  return true if type_sig.length == 0
  stack_type = stack[-(type_sig.length)..-1].map(&:qtype)
  types_eq = type_sig.zip(stack_type)
    .map { |sig, type| type_match(sig, type) }
    .inject(true) { |a, b| a && b}
  return types_eq, type_sig, stack_type
end

# converts a qtype to a qitem representation (used in the `type` function)
def type_to_qitem t
  return QSym.new(t.to_s) if t.is_a? Symbol
  QQuote.new([], t.map { |x| type_to_qitem x })
end
