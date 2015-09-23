require 'shellwords'

module Docker::Compose
  module Shell
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
    def self.command(words, opts)
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
    # @param [Array] words
    # @return [Array] a pair of Integer exitstatus and String output
    def self.run(words)
      cmd = words.join ' '
      output = `#{cmd} 2> /dev/null`
      result = $?.exitstatus
      [result, output]
    end
  end
end
