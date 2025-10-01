module RSMP
  class Logger
    attr_accessor :settings

    DEFAULT_SETTINGS = {
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
      'tabs' => '-',

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
    }.freeze

    DEFAULT_LENGTHS = {
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
    }.freeze

    IGNORABLE_TYPE_GROUPS = {
      'versions' => ['Version'],
      'statuses' => %w[StatusRequest StatusSubscribe StatusUnsubscribe StatusResponse StatusUpdate],
      'commands' => %w[CommandRequest CommandResponse],
      'watchdogs' => 'Watchdog',
      'alarms' => ['Alarm'],
      'aggregated_status' => %w[AggregatedStatus AggregatedStatusRequest]
    }.freeze

    OUTPUT_TRANSFORMS = {
      prefix: ->(logger, _item, _part) { logger.settings['prefix'] unless logger.settings['prefix'] == false },
      timestamp: ->(_logger, _item, part) { Clock.to_s(part) },
      direction: ->(_logger, _item, part) { { in: 'In', out: 'Out' }[part] },
      level: ->(_logger, _item, part) { part.capitalize },
      id: lambda { |_logger, item, _part|
        Logger.shorten_message_id(item[:message].m_id, 4) if item[:message]
      },
      json: ->(_logger, item, _part) { item[:message]&.json },
      exception: lambda { |_logger, _item, exception|
        next unless exception

        [exception.class, exception.backtrace].flatten.compact.join("\n")
      }
    }.freeze

    LEVEL_COLORS = {
      'info' => 'white',
      'log' => 'light_blue',
      'statistics' => 'light_black',
      'warning' => 'light_yellow',
      'error' => 'red',
      'debug' => 'light_black',
      'collect' => 'light_black'
    }.freeze

    ACK_TYPES = %w[MessageAck MessageNotAck].freeze

    def initialize(settings = {})
      @ignorable = IGNORABLE_TYPE_GROUPS
      @settings = build_settings(settings)
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

    def output?(item, force: false)
      return false if muted?(item)
      return false if inactive_without_force?(force)
      return false if level_muted?(item[:level])

      message_visible?(item)
    end

    def output(level, str)
      return if str.empty? || /^\s+$/.match(str)

      str = colorize level, str
      @stream.puts str
      @stream.flush
    end

    def colorize(level, str)
      return str if @settings['color'] == false || @settings['color'].nil?

      return colorize_with_palette(level, str) if palette_based_colorization?

      emphasize_if_ack(level, str)
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

    def build_output(item)
      parts = []
      output_keys.each do |key|
        transform = OUTPUT_TRANSFORMS[key]
        build_part(parts, item, key) do |part|
          transform ? transform.call(self, item, part) : part
        end
      end

      parts.join('  ').chomp(@settings['tabs'].to_s).rstrip
    end
  end
end
