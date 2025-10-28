module RSMP
  class Logger
    # Handles filtering logic for log output
    module Filtering
      def level_enabled?(item)
        return false if @settings['info'] == false && item[:level] == :info
        return false if @settings['debug'] != true && item[:level] == :debug
        return false if @settings['statistics'] != true && item[:level] == :statistics
        return false if @settings['test'] != true && item[:level] == :test

        true
      end

      def message_ignored?(item)
        return false unless item[:message]

        type = item[:message].type
        ack = %w[MessageAck MessageNotAck].include?(type)
        return true unless ignorable?(type, ack, item)
        return true unless acknowledgement_enabled?(ack, item)

        false
      end

      def ignorable?(type, ack, item)
        @ignorable.each_pair do |key, types|
          ignore = [types].flatten
          next unless @settings[key] == false
          return false if ignore.include?(type)

          return false if ack && item[:message].original && ignore.include?(item[:message].original.type)
        end
        true
      end

      def acknowledgement_enabled?(ack, item)
        return true unless ack
        return true if @settings['acknowledgements'] != false
        return true if %i[not_acknowledged warning error].include?(item[:level])

        false
      end

      def output?(item, force: false)
        return false if muted?(item)
        return false if @settings['active'] == false && force != true
        return false unless level_enabled?(item)
        return false if message_ignored?(item)

        true
      end
    end
  end
end
