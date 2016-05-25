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
      message = format("'%s' failed with status %d: %s", cmd, status, brief)
      super(message)
    end
  end
end
