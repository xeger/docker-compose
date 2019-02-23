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
    # A Regex that matches all ANSI escape sequences.
    ANSI = /\033\[([0-9];?)+[a-z]/

    # Working directory (determines compose project name); default is Dir.pwd
    attr_reader :dir

    # Project file; default is 'docker-compose.yml'
    attr_reader :file

    # Reference to the last executed command.
    attr_reader :last_command

    def initialize(shell = Backticks::Runner.new(buffered: [:stderr], interactive: true),
                   dir: Dir.pwd, file: 'docker-compose.yml')
      @shell = shell
      @dir = dir
      @file = file
      @last_command = nil
    end

    # Validate docker-compose file and return it as Hash
    # @return [Hash] the docker-compose config file
    # @raise [Error] if command fails
    def config(*args)
      config = strip_ansi(run!('config', *args))
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

    def ps(*services)
      inter = @shell.interactive
      @shell.interactive = false

      lines = strip_ansi(run!('ps', {q: true}, services)).split(/[\r\n]+/)
      containers = Collection.new

      lines.each do |id|
        containers << docker_ps(strip_ansi(id))
      end

      containers
    ensure
      @shell.interactive = inter
    end

    # Idempotently up the given services in the project.
    # @param [Array] services list of String service names to run
    # @param [Boolean] detached if true, to start services in the background;
    #   otherwise, monitor logs in the foreground and shutdown on Ctrl+C
    # @param [Integer] timeout how long to wait for each service to start
    # @param [Boolean] build if true, build images before starting containers
    # @param [Boolean] no_build if true, don't build images, even if they're
    #   missing
    # @param [Boolean] no_deps if true, just run specified services without
    #   running the services that they depend on
    # @return [true] always returns true
    # @raise [Error] if command fails
    def up(*services,
           abort_on_container_exit: false,
           detached: false, timeout: 10, build: false,
           exit_code_from: nil,
           no_build: false, no_deps: false, no_start: false)
      o = opts(
               abort_on_container_exit: [abort_on_container_exit, false],
               d: [detached, false],
               timeout: [timeout, 10],
               build: [build, false],
               exit_code_from: [exit_code_from, nil],
               no_build: [no_build, false],
               no_deps: [no_deps, false],
               no_start: [no_start, false]
      )
      run!('up', o, services)
      true
    end

    # Idempotently scales the number of containers for given services in the project.
    # @param [Hash] container_count per service, e.g. {web: 2, worker: 3}
    # @param [Integer] timeout how long to wait for each service to scale
    def scale(container_count, timeout: 10)
      args = container_count.map {|service, count| "#{service}=#{count}"}
      o = opts(timeout: [timeout, 10])
      run!('scale', o, *args)
    end

    # Take the stack down
    def down(remove_volumes: false)
      run!('down', opts(v: [!!remove_volumes, false]))
    end

    # Pull images of services
    # @param [Array] services list of String service names to pull
    def pull(*services)
      run!('pull', *services)
    end

    def rm(*services, force: false, volumes: false)
      o = opts(f: [force, false], v: [volumes, false])
      run!('rm', o, services)
    end

    # Idempotently run an arbitrary command with a service container.
    # @param [String] service name to run
    # @param [String] cmd command statement to run
    # @param [Boolean] detached if true, to start services in the background;
    #   otherwise, monitor logs in the foreground and shutdown on Ctrl+C
    # @param [Boolean] no_deps if true, just run specified services without
    #   running the services that they depend on
    # @param [Array] env a list of environment variables (see: -e flag)
    # @param [Array] volumes a list of volumes to bind mount (see: -v flag)
    # @param [Boolean] rm remove the container when done
    # @param [Boolean] no_tty disable pseudo-tty allocation (see: -T flag)
    # @param [String] user run as specified username or uid (see: -u flag)
    # @raise [Error] if command fails
    def run(service, *cmd, detached: false, no_deps: false, volumes: [], env: [], rm: false, no_tty: false, user: nil, service_ports: false)
      o = opts(d: [detached, false], no_deps: [no_deps, false], rm: [rm, false], T: [no_tty, false], u: [user, nil], service_ports: [service_ports, false])
      env_params = env.map { |v| { e: v } }
      volume_params = volumes.map { |v| { v: v } }
      run!('run', o, *env_params, *volume_params, service, cmd)
    end

    def restart(*services, timeout:10)
      o = opts(timeout: [timeout, 10])
      run!('restart', o, *services)
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
    def stop(*services, timeout: 10)
      o = opts(timeout: [timeout, 10])
      run!('stop', o, services)
    end

    # Forcibly stop running services.
    # @param [Array] services list of String service names to stop
    # @param [String] name of murderous signal to use, default is 'KILL'
    # @see Signal.list for a list of acceptable signal names
    def kill(*services, signal: 'KILL')
      o = opts(signal: [signal, 'KILL'])
      run!('kill', o, services)
    end

    # Figure out which interface(s) and port a given service port has been published to.
    #
    # **NOTE**: if Docker Compose is communicating with a remote Docker host, this method
    # returns IP addresses from the point of view of *that* host and its interfaces. If
    # you need to know the address as reachable from localhost, you probably want to use
    # `Mapper`.
    #
    # @see Docker::Compose::Mapper
    #
    # @param [String] service name of service from docker-compose.yml
    # @param [Integer] port number of port
    # @param [String] protocol 'tcp' or 'udp'
    # @param [Integer] index of container (if multiple instances running)
    # @return [String,nil] an ip:port pair such as "0.0.0.0:32176" or nil if the service is not running
    # @raise [Error] if command fails
    def port(service, port, protocol: 'tcp', index: 1)
      inter = @shell.interactive
      @shell.interactive = false

      o = opts(protocol: [protocol, 'tcp'], index: [index, 1])
      s = strip_ansi(run!('port', o, service, port).strip)
      (!s.empty? && s) || nil
    rescue Error => e
      # Deal with docker-compose v1.11+
      if e.detail =~ /No container found/i
        nil
      else
        raise
      end
    ensure
      @shell.interactive = inter
    end

    # Determine the installed version of docker-compose.
    # @param [Boolean] short whether to return terse version information
    # @return [String, Hash] if short==true, returns a version string;
    #   otherwise, returns a Hash of component-name strings to version strings
    # @raise [Error] if command fails
    def version(short: false)
      o = opts(short: [short, false])
      result = run!('version', o, file: false, dir: false)

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

    def build(*services, force_rm: false, no_cache: false, pull: false)
      o = opts(force_rm: [force_rm, false],
               no_cache: [no_cache, false],
               pull: [pull, false])
      result = run!('build', o, services)
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
      file_args = case @file
      when 'docker-compose.yml'
        []
      when Array
        # backticks sugar can't handle array values; build a list of hashes
        # IMPORTANT: preserve the order of the files so overrides work correctly
        file_args = @file.map { |filepath| { :file => filepath } }
      else
        # a single String (or Pathname, etc); use normal sugar to add it
        [{ file: @file.to_s }]
      end

      @shell.chdir = dir
      @last_command = @shell.run('docker-compose', *file_args, *args).join
      status = @last_command.status
      out = @last_command.captured_output
      err = @last_command.captured_error
      status.success? || fail(Error.new(args.first, status, out+err))
      out
    end

    private

    def docker_ps(id)
      cmd = @shell.run('docker', 'ps', a: true, f: "id=#{id}", no_trunc: true, format: Container::PS_FMT).join
      status, out, err = cmd.status, cmd.captured_output, cmd.captured_error
      raise Error.new('docker ps', status, out+err) unless status.success?
      lines = out.split(/[\r\n]+/)
      return nil if lines.empty?
      l = strip_ansi(lines.shift)
      m = parse(l)
      raise Error.new('docker ps', status, "Cannot parse output: '#{l}'") unless m
      raise Error.new('docker ps', status, "Cannot parse output: '#{l}'") unless m.size == 7
      return Container.new(*m)
    end

    # strip default-valued options. the value of each kw should be a pair:
    #  [0] is present value
    #  [1] is default value
    def opts(**kws)
      res = {}
      kws.each_pair do |kw, v|
        res[kw] = v[0] unless v[0] == v[1]
      end
      res
    end

    # strip all ANSI escape sequences from str
    def strip_ansi(str)
      str.gsub(ANSI, '')
    end

    # Parse a string that consists of a sequence of values enclosed within parentheses.
    # Ignore any bytes that are outside of parentheses. Values may include nested parentheses.
    #
    # @param [String] str e.g. "(foo) ((bar)) ... (baz)"
    # @return [Array] e.g. ["foo", "bar", "baz"]
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
            field << ch
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
