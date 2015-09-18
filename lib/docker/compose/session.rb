module Docker::Compose
  class Session
    def initialize(shell, dir:Dir.pwd, file:'docker-compose.yml')
      @shell = shell
      @dir = dir
      @file = file
    end

    # Run a command
    def up(**opts)
      run!("up", **opts)
    end

    # Run a command and return its output. Provide one or more command words
    # which are joined with ' ' and passed to the shell.
    # @return [String] output of the command
    def run!(*words, **opts)
      result, output = @shell.run(prepare(words, opts))
      (result == 0) || raise(RuntimeError, "#{words.first} failed with status #{result}")
      output
    end

    private def prepare(words, opts)
      cmd = []
      cmd << '--file' << @file if @file
      cmd << '--dir' << @dir if @dir
      cmd.concat(words)
      opts.each do |kw, arg|
        if kw.length == 1
          if arg == true
            cmd << "-#{kw}"
          elsif arg
            cmd << "-#{kw} #{arg}"
          else
            # false/nil: omit the flag entirely
          end
        else
          if arg == true
            cmd << "--#{kw}"
          elsif arg
            cmd << "--#{kw}=#{arg}"
          else
            cmd << "--no-#{kw}"
          end
        end
      end
      cmd
    end
  end
end
