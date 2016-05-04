require 'etc'

module Docker::Compose
  module ShellPrinter
    def self.new
      shell = Etc.getpwuid(Process.uid).shell
      basename = File.basename(shell)

      # Crappy titleize (bash -> Bash)
      basename[0] = basename[0].upcase

      # Find adapter class named after shell; default to posix if nothing found
      klass = const_get(basename.to_sym) rescue Posix

      klass.new
    end
  end
end

require_relative 'shell_printer/posix'
require_relative 'shell_printer/fish'
