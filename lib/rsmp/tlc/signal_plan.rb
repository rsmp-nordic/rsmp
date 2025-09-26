module RSMP
  module TLC
    # A Traffic Light Controller Signal Plan.
    # A signal plan is a description of how all signal groups should change
    # state over time.
    class SignalPlan
      attr_reader :nr, :states, :dynamic_bands, :cycle_time

      def initialize(nr:, cycle_time:, states:, dynamic_bands:)
        @nr = nr
        @states = states
        @dynamic_bands = dynamic_bands || {}
        @cycle_time = cycle_time
      end

      def dynamic_bands_string
        str = @dynamic_bands.map { |band, value| "#{nr}-#{band}-#{value}" }.join(',')
        return nil if str == ''

        str
      end

      def set_band(band, value)
        @dynamic_bands[band.to_i] = value.to_i
      end

      def get_band(band)
        @dynamic_bands[band.to_i]
      end

      def set_cycle_time(cycle_time)
        raise ArgumentError if cycle_time.negative?

        @cycle_time = cycle_time
      end
    end
  end
end
