module RSMP
  class Logger
    # Handles colorization of log output
    module Colorization
      def default_colors
        {
          'error' => { 'color' => 'red' },
          'warning' => { 'color' => 'yellow' },
          'info' => { 'color' => 'white' },
          'log' => { 'color' => 'white', 'mode' => 'dim' },
          'statistics' => { 'color' => 'grey', 'mode' => 'dim' },
          'debug' => { 'color' => 'grey', 'mode' => 'dim' },
          'collect' => { 'color' => 'grey', 'mode' => 'dim' }
        }
      end

      def colorize_with_map(level, str, colors)
        color = colors[level.to_s]
        return str unless color

        if color.is_a?(Hash)
          opts = {}
          opts[:color] = color['color'].to_sym if color['color']
          opts[:mode] = color['mode'].to_sym if color['mode']
          str.colorize(opts)
        else
          str.colorize(color.to_sym)
        end
      end

      def apply_hash_colors(level, str)
        colors = default_colors
        style = @settings['style']
        colors.merge!(style) if style.is_a?(Hash)
        colorize_with_map(level, str, colors)
      end

      def colorize(level, str)
        style = @settings['style']
        return str if style == false || style.nil?

        if style == true || style.is_a?(Hash)
          apply_hash_colors(level, str)
        elsif %i[nack warning error].include?(level)
          str.colorize(style).bold
        else
          str.colorize style
        end
      end
    end
  end
end
