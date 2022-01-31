module RSMP
  module TLC
    # A Traffic Light Controller Signal Plan.
    # A signal plan is a description of how all signal groups should change
    # state over time.
    class SignalPlan
      attr_reader :nr, :states, :dynamic_bands
      def initialize nr:, states:, dynamic_bands:
        @nr = nr
        @states = states
        @dynamic_bands = dynamic_bands || {}
      end

      def dynamic_bands_string
        str = @dynamic_bands.map { |band,value| "#{nr}-#{band}-#{value}" }.join(',')
        return nil if str == ''
        str
      end

      def set_band band, value
        @dynamic_bands[ band.to_i ] = value.to_i
      end

      def get_band band
        @dynamic_bands[ band.to_i ]
      end
    end
  end
end