module Docker::Compose
  # Uses a Session to discover information about services' IP addresses and
  # ports as reachable from the host, then
  class Mapper
    # Pattern that matches an "elided" host or port that should be omitted from
    # output, but is needed to identify a specific container and port.
    ELIDED          = /^\[.+\]$/.freeze

    # Regexp that can be used with gsub to strip elision marks
    REMOVE_ELIDED   = /[\[\]]/.freeze

    BadSubstitution = Class.new(StandardError)
    NoService       = Class.new(RuntimeError)

    # Create an instance of Mapper
    # @param [Docker::Compose::Session] session
    # @param [String] host_ip IPv4 address of the host that is publishing
    #   Docker services (i.e. the `DOCKER_HOST` hostname or IP if you are using
    #   a non-clustered Docker environment)
    # @param [Boolean] strict if true, raise BadSubstitution when unrecognized
    #        syntax is passed to #map; if false, simply return the value without
    #        substituting anything
    def initialize(session, host_ip, strict:true)
      @session = session
      @host_ip = host_ip
      @strict  = strict
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
    # @param [String] value a URI or a host:port pair
    #
    # @raise [BadSubstitution] if a substitution string can't be parsed
    # @raise [NoService] if service is not up or does not publish port
    def map(value)
      uri = URI.parse(value) rescue nil
      pair = value.split(':')

      if uri && uri.scheme && uri.host
        # absolute URI with scheme, authority, etc
        uri.port = published_port(uri.host, uri.port)
        uri.host = @host_ip
        return uri.to_s
      elsif pair.size == 2
        # "host:port" pair; three sub-cases...
        if pair.first =~ ELIDED
          # output only the port
          service = pair.first.gsub(REMOVE_ELIDED, '')
          port = published_port(service, pair.last)
          return port.to_s
        elsif pair.last =~ ELIDED
          # output only the hostname; resolve the port anyway to ensure that
          # the service is running.
          service = pair.first
          port = pair.last.gsub(REMOVE_ELIDED, '')
          published_port(service, port)
          return @host_ip
        else
          # output port:hostname pair
          port = published_port(pair.first, pair.last)
          return "#{@host_ip}:#{port}"
        end
      elsif @strict
        raise BadSubstitution, "Can't understand '#{value}'"
      else
        return value
      end
    end

    # Figure out which host port a given service's port has been published to,
    # and/or whether that service is running. Cannot distinguish between the
    # "service not running" case and the "container port not published" case!
    #
    # @raise [NoService] if service is not up or does not publish port
    # @return [Integer] host port number, or nil if port not published
    def published_port(service, port)
      result = @session.port(service, port)
      Integer(result.split(':').last.gsub("\n", ""))
    rescue RuntimeError
      raise NoService, "Service '#{service}' not running, or does not publish port '#{port}'"
    end
  end
end
