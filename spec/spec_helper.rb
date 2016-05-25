$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'docker/compose'

begin
  require 'pry'
rescue LoadError
  # bah!
end