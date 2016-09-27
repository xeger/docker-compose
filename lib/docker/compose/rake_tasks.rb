# encoding: utf-8
require 'json'
require 'rake/tasklib'
require 'shellwords'

# In case this file is required directly
require 'docker/compose'

# Only used here, so only required here
require 'docker/compose/shell_printer'

module Docker::Compose
  class RakeTasks < Rake::TaskLib
    # Set the directory in which docker-compose commands will be run. Default
    # is the directory in which Rakefile is located.
    #
    # @return [String]
    attr_accessor :dir

    # Set the name of the docker-compose file. Default is`docker-compose.yml`.
    # @return [String]
    attr_accessor :file

    # Provide a mapping of environment variables that should be set in
    # _host_ processes, e.g. when running docker:compose:env or
    # docker:compose:host.
    #
    # The values of the environment variables can refer to names of services
    # and ports defined in the docker-compose file, and this gem will substitute
    # the actual IP and port that the containers are reachable on. This allows
    # commands invoked via "docker:compose:host" to reach services running
    # inside containers.
    #
    # @see Docker::Compose::Mapper for information about the substitution syntax
    attr_accessor :host_env

    # Extra environment variables to set before invoking host processes. These
    # are set _in addition_ to server_env, but are not substituted in any way
    # and must not contain any service information.
    #
    # Extra host env should be disjoint from host_env; if there is overlap
    # between the two, then extra_host_env will "win."
    attr_accessor :extra_host_env

    # Services to bring up with `docker-compose up` before running any hosted
    # command. This is useful if your `docker-compose.yml` contains a service
    # definition for the app you will be hosting; if you host the app, you
    # want to specify all of the _other_ services, but not the app itself, since
    # that will run on the host.
    attr_accessor :host_services

    # Namespace to define the rake tasks under. Defaults to "docker:compose'.
    attr_accessor :rake_namespace

    # Construct Rake wrapper tasks for docker-compose. If a block is given,
    # yield self to the block before defining any tasks so their behavior
    # can be configured by calling #server_env=, #file= and so forth.
    def initialize
      self.dir = Rake.application.original_dir
      self.file = 'docker-compose.yml'
      self.host_env = {}
      self.extra_host_env = {}
      self.rake_namespace = 'docker:compose'
      yield self if block_given?

      @shell = Backticks::Runner.new
      @session = Docker::Compose::Session.new(@shell, dir: dir, file: file)
      @net_info = Docker::Compose::NetInfo.new
      @shell_printer = Docker::Compose::ShellPrinter.new

      @shell.interactive = true

      define
    end

    def define
      namespace rake_namespace do
        desc 'Print bash exports with IP/ports of running services'
        task :env do
          @shell.interactive = false # suppress useless 'port' output

          tty = STDOUT.tty?
          tlt = Rake.application.top_level_tasks.include?('docker:compose:env')

          # user invoked this task directly; print some helpful tips on
          # how we intend it to be used.
          print_usage if tty && tlt

          export_env(print: tlt)

          @shell.interactive = true
        end

        desc 'Run command on host, linked to services in containers'
        task :host, [:command] => ['docker:compose:env'] do |_task, args|
          if host_services
            @session.up(*host_services, detached: true)
          else
            @session.up(detached: true)
          end

          exec(args[:command])
        end
      end
    end
    private :define

    # Substitute and set environment variables that point to network ports
    # published by docker-compose services. Optionally also print bash export
    # statements so this information can be made available to a user's shell.
    def export_env(print:)
      Docker::Compose::Mapper.map(host_env,
                                  session: @session,
                                  net_info: @net_info) do |k, v|
        ENV[k] = serialize_for_env(v)
        print_env(k, ENV[k]) if print
      end

      extra_host_env.each do |k, v|
        ENV[k] = serialize_for_env(v)
        print_env(k, ENV[k]) if print
      end
    end
    private :export_env

    # Transform a Ruby value into a String that can be stored in the
    # environment. This accepts nil, String, or Array and returns nil, String
    # or JSON-serialized Array.
    def serialize_for_env(v)
      case v
      when String
        v
      when NilClass
        nil
      when Array
        JSON.dump(v)
      else
        fail ArgumentError, "Can't represent a #{v.class} in the environment"
      end
    end
    private :serialize_for_env

    # Print an export or unset statement suitable for user's shell
    def print_env(k, v)
      if v
        puts @shell_printer.export(k, v)
      else
        puts @shell_printer.unset(k)
      end
    end
    private :print_env

    def print_usage
      command = "rake #{rake_namespace}:env"
      command = 'bundle exec ' + command if defined?(Bundler)
      puts @shell_printer.comment('To export these variables to your shell, run:')
      puts @shell_printer.comment(@shell_printer.eval_output(command))
    end
    private :print_usage
  end
end
