require_relative 'compose/version'
require_relative 'compose/error'
require_relative 'compose/shell'
require_relative 'compose/session'
require_relative 'compose/net_info'
require_relative 'compose/mapper'

module Docker
  module Compose
    # Create a new session with default options.
    def self.new
      Session.new
    end
  end
end
