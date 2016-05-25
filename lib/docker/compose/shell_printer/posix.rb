# encoding: utf-8
module Docker::Compose::ShellPrinter
  # Printer that works with any POSIX-compliant shell e.g. sh, bash, zsh
  class Posix
    def comment(value)
      format('# %s', value)
    end

    def eval_output(command)
      format('eval "$(%s)"', command)
    end

    def export(name, value)
      format('export %s=%s', name, single_quoted_escaped(value))
    end

    def unset(name)
      format('unset %s', name)
    end

    protected def single_quoted_escaped(value)
      # "escape" any occurrences of ' in value by closing the single-quoted
      # string, concatenating a single backslash-escaped ' character, and reopening
      # the single-quoted string.
      #
      # This relies on the shell's willingness to concatenate adjacent string
      # literals. Tested under sh, bash and zsh; should work elsewhere.
      escaped = value.gsub("'") { "'\\''" }

      "'#{escaped}'"
    end
  end
end
