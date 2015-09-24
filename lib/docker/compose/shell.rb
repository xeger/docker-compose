require 'open3'
require 'shellwords'

module Docker::Compose
  # An easy-to-use interface for invoking commands and capturing their output.
  # Instances of Shell can be interactive, which prints the command's output
  # to the terminal and also allows the user to interact with the command.
  class Shell
    # Create an instance of Shell.
    # @param [Boolean] interactive if true, stdout/stdin/stderr of the Ruby app
    #   will be shared with the subprocess; otherwise stdout will be captured,
    #   stderr will be discarded, and stdin will be unavailable to the
    #   subprocess.
    def initialize(interactive:false)
      @interactive = interactive
    end

    # Run a shell command consisting of one or more words followed by flags and
    # options specified in **opts.
    #
    # Options are translated to CLI parameters using the following convention:
    # 1) Snake-case symbols are hyphenated, e.g. :no_foo => "--no-foo"
    # 2) boolean values indicate a CLI flag; true includes the flag, false or nil omits it
    # 3) other values indicate a CLI option that has a value.
    # 4) single character values are passed as short options e.g. "-X V"
    # 5) multi-character values are passed as long options e.g. "--XXX=V"
    #
    # @param [Array] words a list of command words
    # @param [Hash] opts a map of CLI options to append to words
    # @return [Array] a pair of Integer exitstatus and String output
    def command(words, opts)
      cmd = words
      opts.each do |kw, arg|
        if kw.length == 1
          if arg == true
            # true: boolean flag
            cmd << "-#{kw}"
          elsif arg
            # truthey: option that has a value
            cmd << "-#{kw} #{Shellwords.escape(arg)}"
          else
            # falsey: omit boolean flag
          end
        else
          kw = kw.to_s.gsub('_','-')
          if arg == true
            # true: boolean flag
            cmd << "--#{kw}"
          elsif arg
            # truthey: option that has a value
            cmd << "--#{kw}=#{Shellwords.escape(arg)}"
          else
            # falsey: omit boolean flag
          end
        end
      end

      run(words)
    end

    # Run a command consisting of a number of words. Perform no translation or
    # substitution.
    #
    # TODO use something better than backticks; capture stderr for debugging
    #
    # @param [Array] argv command to run; argv[0] is program name
    # @return [Array] a pair of Integer exitstatus and String output
    def run(argv)
      stdin, stdout, stderr, thr = Open3.popen3(*argv)

      streams = [stdout, stderr]

      if @interactive
        streams << STDIN
      else
        stdin.close
      end

      output = String.new.force_encoding(Encoding::BINARY)

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

      [status, output]
    end
  end
end
