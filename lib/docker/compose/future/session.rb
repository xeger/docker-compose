require 'yaml'

module Docker::Compose::Future
  module Session
    # Pattern that matches an environment substitution in a docker-compose YML
    # file.
    # @see #substitute
    SUBSTITUTION = /\$\{([A-Z0-9:_-]+)\}/

    # Hook in env-var substitution by aliasing a method chain for run!
    def self.included(host)
      done = host.instance_methods.include?(:run_without_substitution!)
      host.instance_eval do
        alias_method :run_without_substitution!, :run!
        alias_method :run!, :run_with_substitution!
      end unless done
    end

    # Read docker-compose YML; perform environment variable substitution;
    # write a temp file; invoke run! with the new file; delete the temp
    # file afterward.
    #
    # This is a complete reimplementation of run! and we only alias the original
    # to be good citizens.
    def run_with_substitution!(*cmd)
      temp = nil
      project = File.basename(@dir)

      # Find and purge the 'file' flag if it exists; otherwise assume we will
      # substitute our default (session) file.
      fn = nil
      cmd.each do |item|
        fn ||= item.delete(:file) if item.is_a?(Hash)
      end
      fn ||= @file

      # Rewrite YML if the file exists and the file:false "flag" wasn't
      # explicitly passed to us.
      Dir.chdir(@dir) do
        yml = YAML.load(File.read(fn))
        yml = substitute(yml)
        temp = Tempfile.new(fn, @dir)
        temp.write(YAML.dump(yml))
        temp.close

        project_opts = {
          file: temp.path,
          project: File.basename(@dir)
        }

        result, output =
          @shell.command('docker-compose', project_opts, *cmd)
        (result == 0) || raise(RuntimeError,
                               "#{cmd.first} failed with status #{result}")
        output
      end
    ensure
      temp.unlink if temp
    end

    # Simulate the behavior of docker-compose 1.5: replace "${VAR}" sequences
    # with the values of environment variables. Perform this recursively if
    # data is a Hash or Array.
    #
    #
    # @param [Hash,Array,String,Object] data
    # @return [Hash,Array,String,Object] data with all ${ENV} references substituted
    private def substitute(data)
      case data
      when Hash
        result = {}
        data.each_pair { |k, v| result[k] = substitute(v) }
      when Array
        result = []
        data.each { |v| result << substitute(v) }
      when String
        result = data
        while (match = SUBSTITUTION.match(result))
          var = match[1]
          repl = format("${%s}", var)
          result.gsub!(repl, ENV[var])
        end
      else
        result = data
      end

      result
    end
  end
end
