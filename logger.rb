module RSMP
  class Logger
    def self.err str
      $stderr.puts str
      $stderr.flush
    end

    def self.log str
      $stdout.puts str
      $stdout.flush
    end
  end
end