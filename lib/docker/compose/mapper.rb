# encoding: utf-8
module Docker::Compose
  # Uses a Session to discover information about services' IP addresses and
  # ports as reachable from localhost, then maps URLs and other common network
  # address formats so they point to the right host and port.
  #
  # **NOTE**: this class uses some heuristics to deal with cases where the
  # Docker client is talking to a remote server because the `DOCKER_HOST`
  # environment variable is set. In those cases, Mapper tries to determine
  # the IP address of the exposed services as reachable from localhost;
  # it generally makes a correct guess, but in certain super-complex networking
  # scenarios it may guess wrong. Please open a GitHub issue if you find
  # a situation where Mapper provides a wrong answer.
  class Mapper
    # Pattern that matches an "elided" host or port that should be omitted from
    # output, but is needed to identify a specific container and port.
    ELIDED          = /^\[.+\]$/.freeze

    # Regexp that can be used with gsub to strip elision marks
    REMOVE_ELIDED   = /[\[\]]/.freeze

    BadSubstitution = Class.new(StandardError)
    NoService       = Class.new(RuntimeError)

    # Instantiate a mapper; map some environment variables; yield to caller for
    # additional processing.
    #
    # @param [Hash] env a set of keys/values whose values will be mapped
    # @param [Session] session
    # @param [NetInfo] net_info
    # @yield yields with each substituted (key, value) pair
    def self.map(env, session:Session.new, net_info:NetInfo.new)
      mapper = new(session, net_info)
      env.each_pair do |k, v|
        begin
          v = mapper.map(v)
          yield(k, v)
        rescue NoService
          yield(k, nil)
        end
      end
    end

    # Create an instance of Mapper
    #
    # @param [Docker::Compose::Session] session
    # @param [NetInfo] net_info
    def initialize(session=Session.new, net_info=NetInfo.new)
      docker_host = ENV['DOCKER_HOST']
      if docker_host.nil? || docker_host =~ /^(\/|unix|file)/
        # If DOCKER_HOST is blank, or pointing to a local socket, then we
        # can trust the address information returned by `docker-compose port`.
        override_host = nil
      else
        # If DOCKER_HOST is present, assume that containers have bound to
        # whatever IP we reach it at; don't fall victim to docker-compose's
        # dirty lies!
        override_host = net_info.docker_routable_ip
      end

      @session = session
      @override_host = override_host
    end

    # Substitute service hostnames and ports that appear in a URL or a
    # host:port string. If either component of a host:port string is
    # surrounded by square brackets, "elide" that component, removing it
    # from the result but using it to find the correct service and port.
    #
    # @example map MySQL on local docker host with 3306 published to 13847
    #   map("tcp://db:3306") # => "tcp://127.0.0.1:13847"
    #
    # @example map just the hostname of MySQL on local docker host
    #   map("db:[3306]") # => "127.0.0.1"
    #
    # @example map just the port of MySQL on local docker host
    #   map("[db]:3306") # => "13847"
    #
    # @example map an array of database hosts
    #   map(["[db1]:3306", "[db2]:3306"])
    #
    # @param [String,#map] value a URI, host:port pair, or an array of either
    #
    # @return [String,Array] the mapped value with container-names and ports substituted
    #
    # @raise [BadSubstitution] if a substitution string can't be parsed
    # @raise [NoService] if service is not up or does not publish port
    def map(value)
      if value.respond_to?(:map)
        value.map { |e| map_scalar(e) }
      else
        map_scalar(value)
      end
    end

    # Figure out which host port a given service's port has been published to,
    # and/or whether that service is running. Cannot distinguish between the
    # "service not running" case and the "container port not published" case!
    #
    # @raise [NoService] if service is not up or does not publish port
    # @return [Array] (String, Integer) pair of host address and port number
    def host_and_port(service, port)
      result = @session.port(service, port.to_s)
      if result
        result.chomp!
      else
        raise NoService,
              "Service '#{service}' not running, or does not " \
              "publish port '#{port}'"
      end

      host, port = result.split(':')
      host = @override_host if @override_host

      [host, Integer(port)]
    end

    # Map a single string, replacing service names with IPs and container ports
    # with the host ports that they have been mapped to.
    # @param [String] value
    # @return [String]
    def map_scalar(value)
      uri = begin
              URI.parse(value)
            rescue
              nil
            end
      pair = value.split(':')

      if uri && uri.scheme && uri.host
        # absolute URI with scheme, authority, etc
        uri.host, uri.port = host_and_port(uri.host, uri.port)
        return uri.to_s
      elsif pair.size == 2
        # "host:port" pair; three sub-cases...
        if pair.first =~ ELIDED
          # output only the port
          service = pair.first.gsub(REMOVE_ELIDED, '')
          _, port = host_and_port(service, pair.last)
          return port.to_s
        elsif pair.last =~ ELIDED
          # output only the hostname; resolve the port anyway to ensure that
          # the service is running.
          service = pair.first
          port = pair.last.gsub(REMOVE_ELIDED, '')
          host, = host_and_port(service, port)
          return host
        else
          # output port:hostname pair
          host, port = host_and_port(pair.first, pair.last)
          return "#{host}:#{port}"
        end
      else
        fail BadSubstitution, "Can't understand '#{value}'"
      end
    end
    private :map_scalar
  end
end
