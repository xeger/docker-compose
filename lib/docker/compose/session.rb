# encoding: utf-8
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

    def initialize(shell = Backticks::Runner.new(buffered:[:stderr], interactive: true),
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
      inter = @shell.interactive
      @shell.interactive = false

      lines = run!('ps', q:true).split(/[\r\n]+/)
      containers = Collection.new

      lines.each do |id|
        containers << docker_ps(id)
      end

      containers
    ensure
      @shell.interactive = inter
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
           { d: detached, timeout: timeout, no_build: no_build, no_deps: no_deps },
           services)
      true
    end

    # Take the stack down
    def down
      run!('down')
    end

    # Pull images of services
    # @param [Array] services list of String service names to pull
    def pull(*services)
      run!('pull', *services)
    end

    def rm(*services, force:false, volumes:false)
      run!('rm', { f: force, v: volumes }, services)
    end

    # Idempotently run an arbitrary command with a service container.
    # @param [String] service name to run
    # @param [String] cmd command statement to run
    # @param [Boolean] detached if true, to start services in the background;
    #   otherwise, monitor logs in the foreground and shutdown on Ctrl+C
    # @param [Boolean] no_deps if true, just run specified services without
    #   running the services that they depend on
    # @param [Array] env a list of environment variables (see: -e flag)
    # @param [Array] env_vars DEPRECATED alias for env kwarg
    # @param [Boolean] rm remove the container when done
    # @raise [Error] if command fails
    def run(service, *cmd, detached:false, no_deps:false, env:[], env_vars:nil, rm:false)
      # handle deprecated kwarg
      if (env.nil? || env.empty?) && !env_vars.nil?
        env = env_vars
      end

      env_params = env.map { |v| { e: v } }
      run!('run',
           { d: detached, no_deps: no_deps, rm: rm }, *env_params, service, cmd)
    end

    # Pause running services.
    # @param [Array] services list of String service names to run
    def pause(*services)
      run!('pause', *services)
    end

    # Unpause running services.
    # @param [Array] services list of String service names to run
    def unpause(*services)
      run!('unpause', *services)
    end

    # Stop running services.
    # @param [Array] services list of String service names to stop
    # @param [Integer] timeout how long to wait for each service to stop
    # @raise [Error] if command fails
    def stop(*services, timeout:10)
      run!('stop', { timeout: timeout }, services)
    end

    # Forcibly stop running services.
    # @param [Array] services list of String service names to stop
    # @param [String] name of murderous signal to use, default is 'KILL'
    # @see Signal.list for a list of acceptable signal names
    def kill(*services, signal:'KILL')
      run!('kill', { s: signal }, services)
    end

    # Figure out which host a port a given service port has been published to.
    # @param [String] service name of service from docker-compose.yml
    # @param [Integer] port number of port
    # @param [String] protocol 'tcp' or 'udp'
    # @param [Integer] index of container (if multiple instances running)
    # @raise [Error] if command fails
    def port(service, port, protocol:'tcp', index:1)
      run!('port', { protocol: protocol, index: index }, service, port)
    end

    # Determine the installed version of docker-compose.
    # @param [Boolean] short whether to return terse version information
    # @return [String, Hash] if short==true, returns a version string;
    #   otherwise, returns a Hash of component-name strings to version strings
    # @raise [Error] if command fails
    def version(short:false)
      result = run!('version', short: short, file: false, dir: false)

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

    def  build(*services, force_rm:false, no_cache:false, pull:false)
      result = run!('build', services,
                    force_rm:force_rm, no_cache:no_cache, pull:pull)
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
      project_opts = {}
      case @file
        when Array
          # a list of compose files, so keep the order and add them
          # we cannot use the sugar way, since it does only support arrays for a single key

          # create a array of hashmaps with file -> filepath, thats the only way we can pass this to backtick
          compose_file_args = @file.map{ |filepath| {:file => filepath} }
          # ensure we add at the very start keeping the order
          args = compose_file_args + args
        when Hash
          # hashes do not make any sense - we would throw away the keys. Probably do so, but for now, bail out
          raise 'Please use either a list of compose file as array or a simple string for a single file'
        else
          # a single file, just use sugar to add it
          project_opts = {
              file: @file
          }
      end

      Dir.chdir(@dir) do
        cmd = @shell.run('docker-compose', project_opts, *args).join
        status = cmd.status
        out = cmd.captured_output
        err = cmd.captured_error
        status.success? || fail(Error.new(args.first, status, err))
        out
      end
    end

    private

    def docker_ps(id)
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
