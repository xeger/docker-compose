module Docker::Compose
  class Error < RuntimeError
    attr_reader :output

    def initialize(cmd, status, output)
      @output = output
      super(format("'%s' failed with status %d; %s",
                   cmd, status, detail(status, output)))
    end

    # Use a simple heuristic to decide on a (hopefully) useful error message
    # given a failed docker-compose invocation.
    #
    # @param [String] output
    private def detail(status, output)
      brief = output.split("\n").first
      if brief.nil? || brief.empty?
        case status
        when 1
          'is DOCKER_HOST set correctly?'
        else
          '(no output)'
        end
      else
        brief
      end

    end
  end
end