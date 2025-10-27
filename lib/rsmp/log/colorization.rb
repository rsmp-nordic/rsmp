# frozen_string_literal: true

module RSMP
  class Logger
    # Handles colorization of log output
    module Colorization
      def default_colors
        {
          'info' => 'white',
          'log' => 'light_blue',
          'statistics' => 'light_black',
          'warning' => 'light_yellow',
          'error' => 'red',
          'debug' => 'light_black',
          'collect' => 'light_black'
        }
      end

      def colorize_with_map(level, str, colors)
        color = colors[level.to_s]
        color ? str.colorize(color.to_sym) : str
      end

      def apply_hash_colors(level, str)
        colors = default_colors
        colors.merge! @settings['color'] if @settings['color'].is_a?(Hash)
        colorize_with_map(level, str, colors)
      end

      def colorize(level, str)
        return str if @settings['color'] == false || @settings['color'].nil?

        if @settings['color'] == true || @settings['color'].is_a?(Hash)
          apply_hash_colors(level, str)
        elsif %i[nack warning error].include?(level)
          str.colorize(@settings['color']).bold
        else
          str.colorize @settings['color']
        end
      end
    end
  end
end
