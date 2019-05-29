module RSMP
  class Logger

    attr_reader :archive

    def initialize server, settings
      @server = server
      @settings = settings
      @archive = []
    end

    def output? item
      return false if @settings["active"] == false
      if item[:message]
        type = item[:message].type
        ack = type == "MessageAck" || type == "MessageNotAck"
        if @settings["watchdogs"] == false
          return false if type == "Watchdog"
          return false if ack && item[:message].original.type == "Watchdog"
        end
        return false if @settings["acknowledgements"] == false && ack
      end
      true
    end

    def build_output item
      parts = []
      parts << item[:timestamp].to_s.ljust(24) unless @settings["timestamp"] == false
      parts << item[:ip].to_s.ljust(22) unless @settings["ip"] == false
      parts << item[:site_id].to_s.ljust(13) unless @settings["site_id"] == false
      parts << item[:level].to_s.capitalize.ljust(7) unless @settings["level"] == false
      parts << item[:direction].to_s.capitalize.ljust(4) unless @settings["direction"] == false
      parts << item[:str].strip unless @settings["text"] == false
      if item[:message]
        parts << item[:message].json unless @settings["json"] == false
      end
      parts.join(' ').chomp(' ')
    end

    def output level, str
      return if str.empty?
      streams = [$stdout]
      streams << $stderr if level == :error
      streams.each do |stream|
        stream.puts str
      end
    end

    def log item
      @archive << item
      @server.archive_changed
      output item[:level], build_output(item) if output? item
    end

    def only_message
      @archive.select { |item| item[:direction] != nil }
    end
  end
end