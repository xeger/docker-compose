module Docker::Compose
  class Container
    PS_STATUS = /^([A-Za-z]+) ?\(?([0-9]*)\)? ?(.*)$/i

    attr_reader :id, :image, :size, :status, :exitstatus
    attr_reader :names, :labels, :ports, :mounts

    # @param [String] id
    # @param [String] image
    # @param [String,Numeric] size
    # @param [String,#map] status e.g. ['Exited', '0', '3 minutes ago']
    # @param [String,#map] names
    # @param [String,#map] labels
    # @param [String,#map] ports
    # @param [String,#map] mounts
    def initialize(id, image, size, status, names, labels, ports, mounts)
      if size.is_a?(String)
        scalar, units = size.split(' ')
        scalar = size[0].to_i # lazy: invalid --> 0
        mult = case units.downcase
        when 'b'  then 1
        when 'kb' then 1_024
        when 'mb' then 1_024^2
        when 'gb' then 1_024^3
        when 'tb' then 1_024^4
        else
          raise Error.new('Service#new', units, 'Impossibly large unit')
        end
        size = scalar * mult
      end

      if status.is_a?(String)
        status = PS_STATUS.match(status)
        raise Error.new('Service#new', status, 'Unrecognized status') unless status
      end

      names = names.split(',') if names.is_a?(String)
      labels = labels.split(',') if labels.is_a?(String)
      ports = ports.split(',') if ports.is_a?(String)
      mounts = ports.split(',') if mounts.is_a?(String)

      @id = id
      @image = image
      @size = size
      @status = status[1].downcase.to_sym
      @exitstatus = !status[2].empty? && status[2].to_i # sloppy!
      @names = names
      @labels = labels
      @ports = ports
      @mounts = mounts
    end

    # @return [String]
    def name
      names.first
    end

    # @return [Boolean]
    def up?
      self.status == :up
    end
  end
end
