require 'yaml'

module Docker::Compose::Future
  module Session
    BadSubstitution = Class.new(StandardError)

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
    def run_with_substitution!(*words, **opts)
      temp = nil
      project = File.basename(@dir)

      # Rewrite YML if the file exists and the file:false "flag" wasn't
      # explicitly passed to us.
      Dir.chdir(@dir) do
        fn = opts[:file] || @file
        if opts[:file] != false && File.exist?(fn)
          yml = YAML.load(fn)
          yml = substitute(yml)
          temp = Tempfile.new('docker-compose', @dir)
          temp.write(YAML.dump(yml))
          temp.close
          opts = opts.merge(project: project, file: temp.path)
        end
      end

      run_without_substitution!(*words, **opts)
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
