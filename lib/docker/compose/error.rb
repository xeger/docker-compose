# encoding: utf-8
module Docker::Compose
  class Error < RuntimeError
    attr_reader :status, :detail

    # @param [String] cmd
    # @param [Integer] status
    # @param [String] detail
    def initialize(cmd, status, detail)
      @status = status
      @detail = detail

      brief = detail.split("\n").first || '(no output)'

      case status
      when Numeric
        status = status.to_s
      else
        status = "'#{status}'"
      end

      message = format("'%s' failed with status %s: %s", cmd, status, brief)
      super(message)
    end
  end
end
