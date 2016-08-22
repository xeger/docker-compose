# encoding: utf-8
module Docker::Compose
  # Utility that gathers information about the relationship between the host
  # on which the Ruby VM is running and the docker host, then makes an
  # guess about the mutually routable IP addresses of each.
  #
  # This information can be used to tell containers how to connect to ports on
  # the local host, or conversely to tell the local host how to connect to ports
  # published by containers running on the docker host.
  #
  # The heuristic works for most cases encountered in the wild, including:
  #   - DOCKER_HOST is unset (assume daemon listening on 127.0.0.1)
  #   - DOCKER_HOST points to a socket (assume 127.0.0.1)
  #   - DOCKER_HOST points to a tcp, http or https address
  class NetInfo
    # Determine IP addresses of the local host's network interfaces.
    #
    # @return [Array] list of String dotted-quad IPv4 addresses
    def self.ipv4_interfaces
      Socket.getifaddrs
        .map { |i| i.addr.ip_address if i.addr && i.addr.ipv4? }.compact
    end

    # Create a new instance of this class.
    # @param [String] docker_host a URI pointing to the docker host
    # @param [Array] list of String dotted-quad IPv4 addresses of local host
    def initialize(docker_host = ENV['DOCKER_HOST'],
                   my_ips = self.class.ipv4_interfaces)
      docker_host ||= 'unix:/var/run/docker.sock'
      @docker_url = URI.parse(docker_host)
      @my_ips = my_ips
    end

    # Examine local host's network interfaces; figure out which one is most
    # likely to share a route with the given IP address. If no IP address
    # is specified, figure out which IP the Docker daemon is reachable on
    # and use that as the target IP.
    #
    # @param [String] target_ip IPv4 address of target
    #
    # @return [String] IPv4 address of host machine that _may_ be reachable from
    #   Docker machine
    def host_routable_ip(target_ip = docker_routable_ip)
      best_match  = ''
      best_prefix = 0

      target_cps = target_ip.codepoints

      @my_ips.each do |my_ip|
        ip_cps = my_ip.codepoints
        prefix = 0
        ip_cps.each_with_index do |cp, i|
          break unless target_cps[i] == cp
          prefix = i
        end

        if prefix > best_prefix
          best_match = my_ip
          best_prefix = prefix
        end
      end

      best_match
    end

    # Figure out the likely IP address of the host pointed to by
    # self.docker_url.
    #
    # @return [String] host-reachable IPv4 address of docker host
    def docker_routable_ip
      case @docker_url.scheme
      when 'tcp', 'http', 'https'
        docker_dns = @docker_url.host
        docker_port = @docker_url.port || 2376
      else
        # Cheap trick: for unix, file or other protocols, assume docker ports
        # are proxied to localhost in addition to other interfaces
        docker_dns = 'localhost'
        docker_port = 2376
      end

      addr = Addrinfo.getaddrinfo(
        docker_dns, docker_port,
        Socket::AF_INET, Socket::SOCK_STREAM).first

      addr && addr.ip_address
    end
  end
end
