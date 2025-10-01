module RSMP
  class Logger
    private

    def build_settings(settings)
      source = (settings || {}).transform_keys(&:to_s)
      merged = DEFAULT_SETTINGS.merge(source)
      merged.to_h do |key, value|
        if value == true && DEFAULT_LENGTHS[key]
          [key, DEFAULT_LENGTHS[key]]
        else
          [key, value]
        end
      end
    end

    def muted?(item)
      item[:ip] && item[:port] && @muted["#{item[:ip]}:#{item[:port]}"]
    end

    def inactive_without_force?(force)
      @settings['active'] == false && force != true
    end

    def level_muted?(level)
      {
        info: @settings['info'] == false,
        debug: @settings['debug'] != true,
        statistics: @settings['statistics'] != true,
        test: @settings['test'] != true
      }[level] || false
    end

    def message_visible?(item)
      message = item[:message]
      return true unless message

      type = message.type
      ack = ACK_TYPES.include?(type)

      @ignorable.each_pair do |key, types|
        next unless @settings[key] == false

        ignore = Array(types)
        return false if ignore.include?(type)

        next unless ack && message.original

        return false if ignore.include?(message.original.type)
      end

      return false if hide_acknowledgement?(ack, item[:level])

      true
    end

    def hide_acknowledgement?(ack, level)
      ack && @settings['acknowledgements'] == false &&
        %i[not_acknowledged warning error].include?(level) == false
    end

    def palette_based_colorization?
      @settings['color'] == true || @settings['color'].is_a?(Hash)
    end

    def colorize_with_palette(level, str)
      colors = LEVEL_COLORS.dup
      colors.merge!(@settings['color']) if @settings['color'].is_a?(Hash)
      color = colors[level.to_s]
      color ? str.colorize(color.to_sym) : str
    end

    def emphasize_if_ack(level, str)
      if %i[nack warning error].include?(level)
        str.colorize(@settings['color']).bold
      else
        str.colorize(@settings['color'])
      end
    end

    def output_keys
      @output_keys ||= %i[
        prefix
        index
        author
        timestamp
        ip
        port
        site_id
        component
        direction
        level
        id
        text
        json
        exception
      ]
    end
  end
end
