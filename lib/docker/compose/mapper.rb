module Docker::Compose
  class Mapper
    # Pattern that matches an "elided" host or port that should be omitted from
    # output, but is needed to identify a specific container and port.
    ELIDED          = /^\[.+\]$/.freeze

    NoService = Class.new(RuntimeError)

    def initialize(session)
      @session = session
    end

    # Substitute service names and ports that appear in a Hash of environment
    # variables such that they point to actual IPs and published ports of
    # running containers.
    #
    # @param [Hash] mapping a map of environment variable names to
    #   substitution templates
    # @param [String] client_ip IPv4 address where containers' ports are published
    # @return [Hash] a set of environment-variable keys and values
    #
    # @raise [BadSubstitution] if a substitution string can't be parsed
    # @raise [NoService] if service is not up or does not publish port
    def map(mapping, client_ip:)
      output = {}

      mapping.each do |name, value|
        uri = URI.parse(value) rescue nil
        pair = value.split(':')

        if uri && uri.scheme && uri.host
          # absolute URI with scheme, authority, etc
          uri.port = published_port(uri.host, uri.port)
          uri.host = client_ip
          output[name] = uri.to_s
        elsif pair.size == 2
          # "host:port" pair; three sub-cases...
          if pair.first =~ ELIDED
            # output only the port
            host = pair.first.gsub(/[()]/, '')
            port = published_port(host, pair.second)
            output[name] = port.to_s
          elsif pair.second =~ ELIDED
            # output only the hostname
            output[name] = client_ip
          else
            # output port:hostname pair
            port = published_port(pair.first, pair.second)
            output[name] = "#{client_ip}:#{port}"
          end
        else
          raise BadSubstitution, "Can't understand '#{value}'"
        end
      end

      output
    end

    # Figure out which host port a given service's port has been published to,
    # and/or whether that service is running. Cannot distinguish between the
    # "service not running" case and the "container port not published" case!
    #
    # @raise [NoService] if service is not up or does not publish port
    # @return [Integer] host port number, or nil if port not published
    def published_port(service, port)
      result = @session.run!('port', service, port)
      Integer(result.split(':').last.gsub("\n", ""))
    rescue RuntimeError
      raise NoService, "Service '#{service}' not running, or does not publish port '#{port}'"
    end
  end
end
