require 'docker/compose/future/session'

module Docker::Compose
  # A Ruby OOP interface to a docker-compose session. A session is bound to
  # a particular directory and docker-compose file (which are set at initialize
  # time) and invokes whichever docker-compose command is resident in $PATH.
  #
  # Run docker-compose commands by calling instance methods of this class and
  # passing kwargs that are equivalent to the CLI options you would pass to
  # the command-line tool.
  #
  # Note that the Ruby command methods usually expose a _subset_ of the options
  # allowed by the docker-compose CLI, and that options are sometimes renamed
  # for clarity, e.g. the "-d" flag always becomes the "detached:" kwarg.
  class Session
    def initialize(shell=Docker::Compose::Shell.new,
                   dir:Dir.pwd, file:'docker-compose.yml')
      @shell = shell
      @dir = dir
      @file = file
    end

    # Monitor the logs of one or more containers.
    # @param [Array] services list of String service names to show logs for
    # @return [true] always returns true
    # @raise [RuntimeError] if command fails
    def logs(*services)
      run!(["logs" + services])
      true
    end

    # Idempotently run services in the project,
    # @param [Array] services list of String service names to run
    # @param [Boolean] detached if true, to start services in the background;
    #   otherwise, monitor logs in the foreground and shutdown on Ctrl+C
    # @param [Integer] timeout how long to wait for each service to stostart
    # @param [Boolean] no_build if true, to skip building images for services
    #   that have a `build:` instruction in the docker-compose file
    # @param [Boolean] no_deps if true, just run specified services without
    #   running the services that they depend on
    # @return [true] always returns true
    # @raise [RuntimeError] if command fails
    def up(*services,
           detached:false, timeout:10, no_build:false, no_deps:false)
      run!(*(["up"] + services),
           d:detached, timeout:timeout, no_build:no_build, no_deps:no_deps)
      true
    end

    # Stop running services.
    # @param [Array] services list of String service names to stop
    # @param [Integer] timeout how long to wait for each service to stop
    def stop(*services, timeout:10)
      run!(["stop"] + services, timeout:timeout)
    end

    # Determine the installed version of docker-compose.
    # @param [Boolean] short whether to return terse version information
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

    # Run a docker-compose command. This does not validate options or flags;
    # use with caution!
    #
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
