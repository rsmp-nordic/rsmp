module RSMP
  module Logger
    def err str
      $stderr.puts str
      $stderr.flush
    end

    def log str
      $stdout.puts str
      $stdout.flush
    end

    def format_connection c
      format_info(c[:now], c[:ip], c[:port])
    end

    def format_message c, e
      format_info(e.now, c[:ip], c[:port], e.line.inspect)
    end

    def format_info now, ip, port, line=""
      ip_port = "#{ip}:#{port}"
      "#{ip_port.ljust 22} #{line}"
    end

    def format_time t
      fraction = t.to_f - t.to_i
      millisecond = (fraction*1000).round
      "#{t.strftime("%F %T")}.#{sprintf('%.3d', millisecond)}"
    end
  end
end