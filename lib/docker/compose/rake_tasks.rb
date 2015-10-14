require 'rake/tasklib'

# In case this file is required directly
require 'docker/compose'

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

    # Provide a mapping of environment variables that should be set in the
    # _host_ shell for docker:compose:env or docker:compose:server.
    # The values of the environment variables can refer to names of services
    # and ports defined in the docker-compose file, and this gem will query
    # docker-compose to find out which host IP and port the services are
    # reachable on. This allows components running on the host to connect to
    # services running inside containers.
    #
    # @see Docker::Compose::Mapper for information about the substitution syntax
    attr_accessor :env

    # Extra environment variables that should be set before invoking the command
    # specified for docker:compose:server. These are set _in addition_ to env
    # (and should be disjoint from env), and do not necessarily need to map the
    # location of a container; they can be simple extra env values that are
    # useful to change the server's behavior when it runs in cooperation
    # with containers.
    #
    # If there is overlap between env and server_env, then keys of server_env
    # will "win"; they are set last.
    attr_accessor :server_env

    # Command to exec on the _host_ when someone invokes docker:compose:server.
    # This is used to start up all containers and then run a server that
    # depends on them and is properly linked to them.
    attr_accessor :server

    # Construct Rake wrapper tasks for docker-compose. If a block is given,
    # yield self to the block before defining any tasks so their behavior
    # can be configured by calling #env=, #file= and so forth.
    def initialize
      self.dir = Rake.application.original_dir
      self.file = 'docker-compose.yml'
      self.env = {}
      self.server_env = {}
      yield self if block_given?

      @shell = Docker::Compose::Shell.new
      @session = Docker::Compose::Session.new(@shell, dir:dir, file:file)
      @net_info = Docker::Compose::NetInfo.new

      define
    end

    private def define
      namespace :docker do
        namespace :compose do
          desc 'Print bash exports with IP/ports of running services'
          task :env do
            @shell.interactive = false # suppress useless 'port' output

            if Rake.application.top_level_tasks.include? 'docker:compose:env'
              # This task is being run as top-level task; set process
              # environment _and_ print bash export commands to stdout.
              # Also print usage hints if user invoked rake directly vs.
              # eval'ing it's output
              print_usage if STDOUT.tty?
              export_env(print:true)
            else
              # This task is a dependency of something else; just export the
              # environment variables for use in-process by other Rake tasks.
              export_env(print:false)
            end
          end

          desc 'Launch services needed to run this application'
          task :up do
            @shell.interactive = true # let user see what's happening
            @session.up(detached:true)
          end

          desc 'Tail logs of all running services'
          task :logs do
            @session.logs
          end

          desc 'Stop services needed to run this application'
          task :stop do
            @session.stop
          end

          desc 'Run application on the host, linked to services in containers'
          task :server => ['docker:compose:up', 'docker:compose:env'] do
            exec(self.server)
          end
        end
      end
    end

    # Substitute and set environment variables that point to network ports
    # published by docker-compose services. Optionally also print bash export
    # statements so this information can be made available to a user's shell.
    private def export_env(print:)
      # First, do env substitutions in strict mode; don't catch BadSubstitution
      # so the caller knows when he has a bogus value
      mapper = Docker::Compose::Mapper.new(@session,
                                           @net_info.docker_routable_ip)
      self.env.each_pair do |k, v|
        begin
          v = mapper.map(v)
          ENV[k] = v
          print_env(k, v) if print
        rescue Docker::Compose::Mapper::NoService
          ENV[k] = nil
          print_env(k, nil) if print
        end
      end

      # Next, do server substitutions in non-strict mode since server_env
      # can contain arbitrary values.
      mapper = Docker::Compose::Mapper.new(@session,
                                           @net_info.docker_routable_ip,
                                           strict:false)
      self.server_env.each_pair do |k, v|
        v = mapper.map(v)
        ENV[k] = v
        print_env(k, v) if print
      end
    end

    # Print a bash export or unset statement
    private def print_env(k, v)
      if v
        puts format('export %s=%s', k, v)
      else
        puts format('unset %s # service not running', k)
      end
    end

    private def print_usage
      be = 'bundle exec ' if defined?(Bundler)
      puts %Q{# To export these variables to your shell, run:}
      puts %Q{#   eval "$(#{be}rake docker:compose:env)"}
    end
  end
end
