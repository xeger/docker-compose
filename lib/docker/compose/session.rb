require 'backticks'
require 'yaml'

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

    # Validate docker-compose file and return it as Hash
    # @return [Hash] the docker-compose config file
    # @raise [Error] if command fails
    def config(*args)
      config = run!('config', *args)
      YAML.load(config)
    end

    # Monitor the logs of one or more containers.
    # @param [Array] services list of String service names to show logs for
    # @return [true] always returns true
    # @raise [Error] if command fails
    def logs(*services)
      run!('logs', services)
      true
    end

    def ps()
      lines = run!('ps', q:true).split(/[\r\n]+/)
      containers = Collection.new

      lines.each do |id|
        containers << docker_ps(id)
      end

      containers
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

    def rm(*services, force:false, volumes:false, all:true)
      run!('rm', {f:force, v:volumes, a:all}, services)
    end

    # Idempotently run an arbitrary command with a service container.
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

    private

    def docker_ps(id)
      # docker ps -f id=c9e116fe1ce9732f7f715386078a317d8e322adaf98fa41507d1077d3af9ba02

      cmd = @shell.run('docker', 'ps', a:true, f:"id=#{id}", format:Container::PS_FMT).join
      status, out, err = cmd.status, cmd.captured_output, cmd.captured_error
      raise Error.new('docker ps', status, "Unexpected output") unless status.success?
      lines = out.split(/[\r\n]+/)
      return nil if lines.empty?
      l = lines.shift
      m = parse(l)
      raise Error.new('docker ps', status, "Cannot parse output: '#{l}'") unless m
      return Container.new(*m)
    end

    # parse values enclosed within parentheses; values may contain nested
    # matching pairs of parentheses
    def parse(str)
      fields = []
      nest = 0
      field = ''
      str.each_char do |ch|
        got = false
        if nest == 0
          if ch == '('
            nest += 1
          end
        else
          if ch == '('
            nest += 1
          elsif ch == ')'
            nest -= 1
            if nest == 0
              got = true
            else
              field << ch
            end
          else
            field << ch
          end
        end

        if got
          fields << field
          field = ''
        end
      end

      fields
    end
  end
end
