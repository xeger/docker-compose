require_relative 'compose/version'
require_relative 'compose/shell'
require_relative 'compose/session'
require_relative 'compose/net'

module Docker
  module Compose
    # Create a new session.
    def self.new
      Session.new(Shell)
    end
  end
end
