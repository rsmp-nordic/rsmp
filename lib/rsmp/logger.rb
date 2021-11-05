module RSMP
  class Logger

    attr_accessor :settings
    
    def initialize settings={}
      defaults = {
        'prefix'=>nil,
        'active'=>false,
        'path'=>nil,
        'stream'=>nil,
        'author'=>false,
        'color'=>true,
        'site_id'=>true,
        'component'=>false,
        'level'=>false,
        'ip'=>false,
        'port'=>false,
        'index'=>false,
        'timestamp'=>true,
        'json'=>false,
        'debug'=>false,
        'statistics'=>false,
        'hide_ip_and_port' => false,
        'acknowledgements' => false
      }
      if settings
        @settings = defaults.merge settings
      else
        @settings = defaults
      end

      @muted = {}

      setup_output_destination
    end

    def setup_output_destination
      if @settings['stream']
        @stream = @settings['stream']
      elsif @settings['path']
        @stream = File.open(@settings['path'],'a')  # appending
      else
        @stream = $stdout
      end
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

    def output? item, force=false
      return false if item[:ip] && item[:port] && @muted["#{item[:ip]}:#{item[:port]}"]
      return false if @settings["active"] == false && force != true
      return false if @settings["info"] == false && item[:level] == :info
      return false if @settings["debug"] != true && item[:level] == :debug
      return false if @settings["statistics"] != true && item[:level] == :statistics
      return false if @settings["test"] != true && item[:level] == :test

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
      str = colorize level, str
      @stream.puts str
      @stream.flush
    end

    def colorize level, str
      if @settings["color"] == false || @settings["color"] == nil
        str
      elsif @settings["color"] == true || @settings["color"].is_a?(Hash)
        colors = {
          'info' => 'white',
          'log' => 'light_blue',
          'test' => 'light_magenta',
          'statistics' => 'light_black',
          'not_acknowledged' => 'cyan',
          'warning' => 'light_yellow',
          'error' => 'red',
          'debug' => 'light_black'
        }
        colors.merge! @settings["color"] if @settings["color"].is_a?(Hash)
        if colors[level.to_s]
          str.colorize colors[level.to_s].to_sym
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

    def log item, force:false
      if output?(item, force)
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

    def dump archive, force:false, num:nil
      num ||= archive.items.size
      log = archive.items.last(num).map do |item|
        str = build_output item
        str = colorize item[:level], str
      end
      log.join("\n")
    end
  
    def build_output item
      parts = []
      parts << "#{@settings['prefix']} " if @settings['prefix']
      parts << item[:index].to_s.ljust(7) if @settings["index"] == true
      parts << item[:author].to_s.ljust(13) if @settings["author"] == true
      parts << Clock.to_s(item[:timestamp]).ljust(24) unless @settings["timestamp"] == false
      parts << item[:ip].to_s.ljust(22) unless @settings["ip"] == false
      parts << item[:port].to_s.ljust(8) unless @settings["port"] == false
      parts << item[:site_id].to_s.ljust(13) unless @settings["site_id"] == false
      parts << item[:component_id].to_s.ljust(18) unless @settings["component"] == false
      
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