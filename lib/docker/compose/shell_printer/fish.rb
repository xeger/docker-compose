# encoding: utf-8
module Docker::Compose::ShellPrinter
  # Printer that works with the Friendly Interactive Shell (fish).
  class Fish < Posix
    def eval_output(command)
      format('eval (%s)', command)
    end

    def export(name, value)
      format('set -gx %s %s; ', name, single_quoted_escaped(value))
    end

    def unset(name)
      format('set -ex %s; ', name)
    end
  end
end
