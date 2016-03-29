require 'backticks'

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
    attr_reader :dir, :file

    def initialize(shell=Backticks::Runner.new(interactive:true),
                   dir:Dir.pwd, file:'docker-compose.yml')
      @shell = shell
      @dir = dir
      @file = file
    end

    # Monitor the logs of one or more containers.
    # @param [Array] services list of String service names to show logs for
    # @return [true] always returns true
    # @raise [Error] if command fails
    def logs(*services)
      run!('logs', services)
      true
    end

    # Idempotently up the given services in the project.
    # @param [Array] services list of String service names to run
    # @param [Boolean] detached if true, to start services in the background;
    #   otherwise, monitor logs in the foreground and shutdown on Ctrl+C
    # @param [Integer] timeout how long to wait for each service to stostart
    # @param [Boolean] no_build if true, to skip building images for services
    #   that have a `build:` instruction in the docker-compose file
    # @param [Boolean] no_deps if true, just run specified services without
    #   running the services that they depend on
    # @return [true] always returns true
    # @raise [Error] if command fails
    def up(*services,
           detached:false, timeout:10, no_build:false, no_deps:false)
      run!('up',
           {d:detached, timeout:timeout, no_build:no_build, no_deps:no_deps},
           services)
      true
    end

    # Idempotently run a service in the project.
    # @param [String] service name to run
    # @param [String] cmd command statement to run
    # @param [Boolean] detached if true, to start services in the background;
    #   otherwise, monitor logs in the foreground and shutdown on Ctrl+C
    # @param [Boolean] no_deps if true, just run specified services without
    #   running the services that they depend on
    # @param [Array] env_vars a list of environment variables (see: -e flag)
    # @param [Boolean] rm remove the container when done
    # @raise [Error] if command fails
    def run(service, *cmd, detached:false, no_deps:false, env_vars:[], rm:false)
      formated_vars = env_vars.map{|v| {e: v}}
      run!('run',
           {d:detached, no_deps:no_deps, rm:rm}, *formated_vars, service, cmd)
    end

    # Stop running services.
    # @param [Array] services list of String service names to stop
    # @param [Integer] timeout how long to wait for each service to stop
    # @raise [Error] if command fails
    def stop(*services, timeout:10)
      run!('stop', {timeout:timeout}, services)
    end

    # Figure out which host a port a given service port has been published to.
    # @param [String] service name of service from docker-compose.yml
    # @param [Integer] port number of port
    # @param [String] protocol 'tcp' or 'udp'
    # @param [Integer] index of container (if multiple instances running)
    # @raise [Error] if command fails
    def port(service, port, protocol:'tcp', index:1)
      run!('port', {protocol:protocol, index:index}, service, port)
    end

    # Determine the installed version of docker-compose.
    # @param [Boolean] short whether to return terse version information
    # @return [String, Hash] if short==true, returns a version string;
    #   otherwise, returns a Hash of component-name strings to version strings
    # @raise [Error] if command fails
    def version(short:false)
      result = run!('version', short:short, file:false, dir:false)

      if short
        result.strip
      else
        lines = result.split(/[\r\n]+/)
        lines.inject({}) do |h, line|
          kv = line.split(/: +/, 2)
          h[kv.first] = kv.last
          h
        end
      end
    end

    # Run a docker-compose command without validating that the CLI parameters
    # make sense. Prepend project and file options if suitable.
    #
    # @see Docker::Compose::Shell#command
    #
    # @param [Array] args command-line arguments in the format accepted by
    #   Backticks::Runner#command
    # @return [String] output of the command
    # @raise [Error] if command fails
    def run!(*args)
      project_opts = {
        file: @file
      }

      Dir.chdir(@dir) do
        cmd = @shell.run('docker-compose', project_opts, *args).join
        status, out, err = cmd.status, cmd.captured_output, cmd.captured_error
        status.success? || raise(Error.new(args.first, status, err))
        out
      end
    end
  end
end
