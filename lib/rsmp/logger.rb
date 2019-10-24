module RSMP
  class Logger

    def initialize settings
      @settings = settings
      @muted = {}
    end

    def mute ip, port
      @muted["#{ip}:#{port}"] = true
    end

    def unmute ip, port
      @muted.delete "#{ip}:#{port}"
    end

    def unmute_all
      @muted = {}
    end

    def output? item
      return false if item[:ip] && item[:port] && @muted["#{item[:ip]}:#{item[:port]}"]
      return false if @settings["active"] == false
      return false if @settings["info"] == false && item[:level] == :info
      return false if @settings["debug"] != true && item[:level] == :debug
      return false if @settings["statistics"] != true && item[:level] == :statistics


      if item[:message]
        type = item[:message].type
        ack = type == "MessageAck" || type == "MessageNotAck"
        if @settings["watchdogs"] == false
          return false if type == "Watchdog"
          if ack
            return false if item[:message].original && item[:message].original.type == "Watchdog"
          end
        end
        return false if ack && @settings["acknowledgements"] == false && 
          [:not_acknowledged,:warning,:error].include?(item[:level]) == false
      end
      true
    end

    def output level, str
      return if str.empty? || /^\s+$/.match(str)
      streams = [$stdout]
      #streams << $stderr if level == :error
      str = colorize level, str
      streams.each do |stream|
        stream.puts str
      end
    end

    def colorize level, str
      #p String.color_samples
      if @settings["color"] == false || @settings["color"] == nil
        str
      elsif @settings["color"] == true
        case level
        when  :error
          str.colorize(:red)
        when :warning
          str.colorize(:light_yellow)
        when :not_acknowledged
          str.colorize(:cyan)
        when :log
          str.colorize(:light_blue)
        when :statistics
          str.colorize(:light_black)
        else
          str
        end
      else
        if level == :nack || level == :warning || level == :error
          str.colorize(@settings["color"]).bold
        else
          str.colorize @settings["color"]
        end
      end
    end

    def log item      
      if output? item
        output item[:level], build_output(item) 
      end
    end

    def self.shorten_message_id m_id, length=4
      if m_id
        m_id[0..length-1].ljust(length)
      else
        ' '*length
      end
    end 

    private
    
    def build_output item
      parts = []
      parts << item[:index].to_s.ljust(7) if @settings["index"] == true
      parts << item[:timestamp].to_s.ljust(24) unless @settings["timestamp"] == false
      parts << item[:ip].to_s.ljust(22) unless @settings["ip"] == false
      parts << item[:site_id].to_s.ljust(13) unless @settings["site_id"] == false
      parts << item[:component_id].to_s.ljust(6) unless @settings["component"] == false
      
      directions = {in:"-->",out:"<--"}
      parts << directions[item[:direction]].to_s.ljust(4) unless @settings["direction"] == false

      parts << item[:level].to_s.capitalize.ljust(7) unless @settings["level"] == false

      
      unless @settings["id"] == false
        length = 4
        if item[:message]
          parts << Logger.shorten_message_id(item[:message].m_id,length)+' '
        else
          parts << " "*(length+1)
        end
      end
      parts << item[:str].to_s.strip unless @settings["text"] == false
      parts << item[:message].json unless @settings["json"] == false || item[:message] == nil

      if item[:exception]
        parts << "#{item[:exception].class.to_s}\n"
        parts << item[:exception].backtrace.join("\n")
      end

      out = parts.join(' ').chomp(' ')
      out
    end

  end
end