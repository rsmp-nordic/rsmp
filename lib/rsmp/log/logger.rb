module RSMP
  class Logger
    include Filtering
    include Colorization

    attr_accessor :settings

    def default_output_settings
      {
        'active' => true,
        'path' => nil,
        'stream' => nil,
        'color' => true,
        'debug' => false,
        'statistics' => false,
        'hide_ip_and_port' => false,
        'acknowledgements' => false,
        'watchdogs' => false,
        'alarms' => true,
        'json' => false,
        'tabs' => '-'
      }
    end

    def default_field_settings
      {
        'prefix' => false,
        'index' => false,
        'author' => false,
        'timestamp' => true,
        'ip' => false,
        'port' => false,
        'site_id' => true,
        'component' => true,
        'direction' => false,
        'level' => false,
        'id' => true,
        'text' => true
      }
    end

    def default_logger_settings
      default_output_settings.merge(default_field_settings)
    end

    def default_field_lengths
      {
        'index' => 7,
        'author' => 13,
        'timestamp' => 24,
        'ip' => 22,
        'port' => 5,
        'site_id' => 19,
        'component' => 19,
        'direction' => 3,
        'level' => 7,
        'id' => 4
      }
    end

    def ignorable_messages
      {
        'versions' => ['Version'],
        'statuses' => %w[StatusRequest StatusSubscribe StatusUnsubscribe StatusResponse StatusUpdate],
        'commands' => %w[CommandRequest CommandResponse],
        'watchdogs' => 'Watchdog',
        'alarms' => ['Alarm'],
        'aggregated_status' => %w[AggregatedStatus AggregatedStatusRequest]
      }
    end

    def apply_default_lengths(settings)
      lengths = default_field_lengths
      settings.to_h do |key, value|
        if value == true && lengths[key]
          [key, lengths[key]]
        else
          [key, value]
        end
      end
    end

    def initialize(settings = {})
      @ignorable = ignorable_messages
      @settings = settings ? default_logger_settings.merge(settings) : default_logger_settings
      @settings = apply_default_lengths(@settings)
      @muted = {}
      setup_output_destination
    end

    def setup_output_destination
      @stream = if @settings['stream']
                  @settings['stream']
                elsif @settings['path']
                  File.open(@settings['path'], 'a') # appending
                else
                  $stdout
                end
    end

    def mute(ip, port)
      @muted["#{ip}:#{port}"] = true
    end

    def unmute(ip, port)
      @muted.delete "#{ip}:#{port}"
    end

    def unmute_all
      @muted = {}
    end

    def muted?(item)
      item[:ip] && item[:port] && @muted["#{item[:ip]}:#{item[:port]}"]
    end

    def level_enabled?(item)
      return false if @settings['info'] == false && item[:level] == :info
      return false if @settings['debug'] != true && item[:level] == :debug
      return false if @settings['statistics'] != true && item[:level] == :statistics
      return false if @settings['test'] != true && item[:level] == :test

      true
    end

    def output(level, str)
      return if str.empty? || /^\s+$/.match(str)

      str = colorize level, str
      @stream.puts str
      @stream.flush
    end

    def log(item, force: false)
      return unless output?(item, force: force)

      output item[:level], build_output(item)
    end

    def self.shorten_message_id(m_id, length = 4)
      if m_id
        m_id[0..(length - 1)].ljust(length)
      else
        ' ' * length
      end
    end

    def dump(archive, num: nil)
      num ||= archive.items.size
      log = archive.items.last(num).map do |item|
        str = build_output item
        colorize item[:level], str
      end
      log.join("\n")
    end

    def build_part(parts, item, key, &block)
      skey = key.to_s
      return unless @settings[skey]

      part = item[key]
      part = yield part if block
      part = part.to_s
      part = part.ljust @settings[skey] if @settings[skey].is_a?(Integer)

      # replace the first char with a dash if string is all whitespace
      part = @settings['tabs'].ljust(part.length) if @settings['tabs'] && part !~ /\S/
      parts << part
    end

    def add_metadata_parts(parts, item)
      build_part(parts, item, :prefix) { @settings['prefix'] if @settings['prefix'] != false }
      build_part(parts, item, :index)
      build_part(parts, item, :author)
      build_part(parts, item, :timestamp) { |part| Clock.to_s part }
    end

    def add_connection_parts(parts, item)
      build_part(parts, item, :ip)
      build_part(parts, item, :port)
      build_part(parts, item, :site_id)
      build_part(parts, item, :component)
    end

    def add_message_parts(parts, item)
      build_part(parts, item, :direction) { |part| { in: 'In', out: 'Out' }[part] }
      build_part(parts, item, :level, &:capitalize)
      build_part(parts, item, :id) { Logger.shorten_message_id(item[:message].m_id, 4) if item[:message] }
      build_part(parts, item, :text)
      build_part(parts, item, :json) { item[:message]&.json }
      build_part(parts, item, :exception) { |e| [e.class, e.backtrace].flatten.join("\n") }
    end

    def add_output_parts(parts, item)
      add_metadata_parts(parts, item)
      add_connection_parts(parts, item)
      add_message_parts(parts, item)
    end

    def build_output(item)
      parts = []
      add_output_parts(parts, item)
      parts.join('  ').chomp(@settings['tabs'].to_s).rstrip
    end
  end
end
