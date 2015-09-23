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
    # _host_ shell when someone runs docker:compose:env. The values of the
    # environment variables can refer to names of services and ports defined
    # in the docker-compose file, and this gem will query docker-compose to
    # find out which host IP and port the services are reachable on. This
    # allows components running on the host to connect to services running
    # inside containers.
    # @see Docker::Compose::Mapper for information about the substitution syntax
    attr_accessor :env

    # Construct Rake wrapper tasks for docker-compose. If a block is given,
    # yield self to the block before defining any tasks so their behavior
    # can be configured by calling #env=, #file= and so forth.
    def initialize
      self.dir = Rake.application.original_dir
      self.file = 'docker-compose.yml'
      self.env = {}
      yield self if block_given?

      @session = Docker::Compose::Session.new(dir:dir, file:file)
      @net_info = Docker::Compose::NetInfo.new

      define
    end

    private def define
      namespace :docker do
        namespace :compose do
          desc 'Print bash exports with IP/ports of running services'
          task :env do
            if Rake.application.top_level_tasks.include? 'docker:compose:env'
              # This task is being run as top-level; print some bash export
              # statements or usage information depending on whether STDOUT
              # is a tty.
              if STDOUT.tty?
                print_usage
              else
                export_env(print:true)
              end
            else
              # This task is a dependency of something else; just export the
              # environment variables for use in-process by other Rake tasks.
              export_env(print:false)
            end
          end

          desc 'Launch services needed to run this application'
          task :up do
            @session.up(detached:true)
            puts 'Watching logs; you can safely Ctrl+C without disrupting ' \
                 'containers.'
            @session.logs
          end

          desc 'Stop services needed to run this application'
          task :stop do
            @session.stop
          end
        end
      end
    end

    # Substitute and set environment variables that point to network ports
    # published by docker-compose services. Optionally also print bash export
    # statements so this information can be made available to a user's shell.
    private def export_env(print:)
      mapper = Docker::Compose::Mapper.new(@session,
                                           @net_info.docker_routable_ip)
      self.env.each_pair do |k, v|
        begin
          v = mapper.map(v)
          puts format('export %s=%s', k, v) if print
          ENV[k] = v
        rescue Docker::Compose::Mapper::NoService
          puts format('unset %s # service not running', k) if print
          ENV[k] = nil
        end
      end
    end

    private def print_usage
      be = 'bundle exec ' if defined?(Bundler)
      puts "# To export container network locations to your environment:"
      puts %Q{eval "$(#{be}rake docker:compose:env)"}
      puts
      puts '# To learn which environment variables we will export:'
      puts %Q{echo "$(#{be}rake docker:compose:env)"}
    end
  end
end
