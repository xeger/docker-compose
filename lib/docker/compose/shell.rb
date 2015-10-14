require 'open3'

module Docker::Compose
  # An easy-to-use interface for invoking commands and capturing their output.
  # Instances of Shell can be interactive, which prints the command's output
  # to the terminal and also allows the user to interact with the command.
  class Shell
    # If true, commands run in the shell will have their stdio streams tied
    # to the parent process so the user can view their output and send input
    # to them. Commands' stdout is still captured normally when they are
    # interactive.
    #
    # Note that interactivity doesn't work very well because we use popen,
    # which uses pipes to communicate with the child process and pipes have
    # a fixed buffer size; the displayed output tends to "lag" behind the
    # actual program, and bytes sent to stdin may not arrive until you send
    # a lot of them!
    #
    # TODO: solve pipe buffering issues, perhaps with a pty...
    #
    # @return [Boolean]
    attr_accessor :interactive

    # Convert Ruby keyword arguments into CLI parameters that are compatible
    # with the syntax of golang's flags package.
    #
    # Options are translated to CLI parameters using the following convention:
    # 1) Snake-case symbols are hyphenated, e.g. :no_foo => "--no-foo"
    # 2) boolean values indicate a CLI flag; true includes the flag, false or nil omits it
    # 3) other values indicate a CLI option that has a value.
    # 4) single character values are passed as short options e.g. "-X V"
    # 5) multi-character values are passed as long options e.g. "--XXX=V"
    #
    def self.options(**opts)
      flags = []

      # Transform opts into golang flags-style command line parameters;
      # append them to the command.
      opts.each do |kw, arg|
        if kw.length == 1
          if arg == true
            # true: boolean flag
            flags << "-#{kw}"
          elsif arg
            # truthey: option that has a value
            flags << "-#{kw}" << arg.to_s
          else
            # falsey: omit boolean flag
          end
        else
          kw = kw.to_s.gsub('_','-')
          if arg == true
            # true: boolean flag
            flags << "--#{kw}"
          elsif arg
            # truthey: option that has a value
            flags << "--#{kw}=#{arg}"
          else
            # falsey: omit boolean flag
          end
        end
      end

      flags
    end

    # Create an instance of Shell.
    def initialize
      @interactive = false
    end

    # Run a shell command whose arguments and flags are expressed using some
    # Rubyish sugar. This method accepts an arbitrary number of positional
    # parameters; each parameter can be a Hash, an array, or a simple Object.
    # Arrays and simple objects are appended to argv as "bare" words; Hashes
    # are translated to golang flags and then appended to argv.
    #
    # @return [Array] an (Integer,String,String) triple of exitstatus, stdout and stderr
    #
    # @example Run docker-compose with complex parameters
    #   command('docker-compose', {file: 'joe.yml'}, 'up', {d:true}, 'mysvc')
    #
    # @see #options for information on Hash-to-flag translation
    def command(*cmd)
      argv = []

      cmd.each do |item|
        case item
        when Array
          # list of words to append to argv
          argv.concat(item.map { |e| e.to_s })
        when Hash
          # list of options to convert to CLI parameters
          argv.concat(self.class.options(item))
        else
          # single word to append to argv
          argv << item.to_s
        end
      end

      run(argv)
    end

    # Run a shell command. Perform no translation or substitution. Return
    # the program's exit status and stdout.
    #
    # @param [Array] argv command to run; argv[0] is program name and the
    #   remaining elements are parameters and flags
    # @return [Array] an (Integer,String,String) triple of exitstatus, stdout and stderr
    private def run(argv)
      stdin, stdout, stderr, thr = Open3.popen3(*argv)

      streams = [stdout, stderr]

      if @interactive
        streams << STDIN
      else
        stdin.close
      end

      output = String.new.force_encoding(Encoding::BINARY)
      error = String.new.force_encoding(Encoding::BINARY)

      until streams.empty? || (streams.length == 1 && streams.first == STDIN)
        ready, _, _ = IO.select(streams, [], [], 1)

        if ready && ready.include?(STDIN)
          input = STDIN.readpartial(1_024) rescue nil
          if input
            stdin.write(input)
          else
            # our own STDIN got closed; proxy to child's stdin
            stdin.close
          end
        end

        if ready && ready.include?(stderr)
          data = stderr.readpartial(1_024) rescue nil
          if data
            error << data
            STDERR.write(data) if @interactive
          else
            streams.delete(stderr)
          end
        end

        if ready && ready.include?(stdout)
          data = stdout.readpartial(1_024) rescue nil
          if data
            output << data
            STDOUT.write(data) if @interactive
          else
            streams.delete(stdout)
          end
        end
      end

      # This blocks until the process exits (which probably already happened,
      # given that we have received EOF on its output streams).
      status = thr.value.exitstatus

      [status, output, error]
    rescue Interrupt
      # Proxy Ctrl+C to our child process
      Process.kill('INT', thr.pid) rescue nil
      raise
    end
  end
end
