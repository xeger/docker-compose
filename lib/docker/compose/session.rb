module Docker::Compose
  class Session
    def initialize(shell, dir:Dir.pwd, file:'docker-compose.yml')
      @shell = shell
      @dir = dir
      @file = file
    end

    # Run a command
    def up
      out = run("up")
    end

    # Run a command and return its output. Provide one or more command words
    # which are joined with ' ' and passed to the shell.
    # @return [String] output of the command
    def run(*words, important:true)
      cmd = []
      cmd.concat(['--file', @file]) if @file
      cmd.concat(['--dir', @dir]) if @dir
      cmd.concat(words)
      result, output = @shell.run(cmd)
      (result == 0) || !important || raise(RuntimeError, "#{words.first} failed with status #{result}")
      output
    end
  end
end
