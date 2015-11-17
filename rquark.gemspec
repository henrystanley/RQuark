
Gem::Specification.new do |s|

  s.name        = 'rquark'
  s.version     = '0.1.1'
  s.summary     = 'Quark, A Functional, Purely Homoiconic, Concatenative Language'
  s.description = 'This is a ruby implementation of the Quark language'
  s.homepage    = 'http://kdt.io/~/quark'
  s.authors     = ['⊥']
  s.platform    = Gem::Platform::RUBY
  s.files       = Dir['lib/*.rb', 'lib/prelude.qrk']
  s.executables = ['rquark']
  s.license     = 'CC0'

  s.add_runtime_dependency 'parslet', '~> 1.6'

end
