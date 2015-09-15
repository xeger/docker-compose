require 'shellwords'

module Docker::Compose
  module Shell
    def self.run(words)
      cmd = words.map { |w| Shellwords.escape(w) }.join ''
      output = `#{cmd}`
      result = $?.exitstatus
      [result, output]
    end
  end
end
