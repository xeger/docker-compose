require 'docker/compose/future/session'

module Docker::Compose
  class Session
    def initialize(shell=Docker::Compose::Shell,
                   dir:Dir.pwd, file:'docker-compose.yml')
      @shell = shell
      @dir = dir
      @file = file
    end

    # Idempotently run all containers in the project,
    # @return [true] always returns true
    # @raise [RuntimeError] if command fails
    def up(*containers,
           detached:false, timeout:10, no_build:false, no_deps:false)
      run!(*(["up"] + containers),
           d:detached, timeout:timeout, no_build:no_build, no_deps:no_deps)
      true
    end

    # Determine the installed version of docker-compose.
    # @return [String, Hash] if short==true, returns a version string;
    #   otherwise, returns a Hash of component names to version strings
    # @raise [RuntimeError] if command fails
    def version(short:false)
      result = run!("version", short:short, file:false, dir:false)

      if short
        result.strip
      else
        lines = result.split("\n")
        lines.inject({}) do |h, line|
          kv = line.split(/: +/, 2)
          h[kv.first] = kv.last
          h
        end
      end
    end

    # Run a docker-compose command.
    # @return [String] output of the command
    # @raise [RuntimeError] if command fails
    def run!(*words, **opts)
      cmd = ['docker-compose']

      # HACK:
      # --file and --project are special: when they occur, they must be passed
      # to docker-compose BEFORE the command. Remove them from opts and turn
      # them into words.
      file = opts.key?(:file) ? opts.delete(:file) : @file
      project = opts.key?(:project) ? opts.delete(:project) : false
      cmd << "--file=#{file}" if file
      cmd << "--project=#{project}" if project

      cmd.concat(words)

      Dir.chdir(@dir) do
        result, output = @shell.command(cmd, opts)
        (result == 0) || raise(RuntimeError,
                               "#{words.first} failed with status #{result}")
        output
      end
    end

    # Simulate behaviors from Docker 1.5
    include Docker::Compose::Future::Session
  end
end
