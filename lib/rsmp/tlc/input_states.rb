module RSMP
  module TLC
    # class that maintains the state of TLC inputs
    # indexing is 1-based since that's how the RSMP messages are specified
    class InputStates
      attr_reader :size

      def initialize(size)
        @size = size
        reset
      end

      def reset
        string_size = @size + 1
        @value = '0' * string_size
        @forced = '0' * string_size
        @forced_value = '0' * string_size
        @actual = '0' * string_size
      end

      def set(input, value)
        check_input input
        report_change(input) do
          @value[input] = to_digit value
          update_actual input
        end
      end

      def set_forcing(input, force: true, forced_value: true)
        check_input input
        report_change(input) do
          @forced[input] = to_digit force
          @forced_value[input] = to_digit forced_value
          update_actual input
        end
      end

      def force(input, forced_value: true)
        report_change(input) do
          set_forcing input, force: true, forced_value: forced_value
        end
      end

      def release(input)
        report_change(input) do
          set_forcing input, force: false, forced_value: false
        end
      end

      def value?(input)
        check_input input
        from_digit? @value[input]
      end

      def forced?(input)
        check_input input
        from_digit? @forced[input]
      end

      def forced_value?(input)
        check_input input
        from_digit? @forced_value[input]
      end

      def actual?(input)
        check_input input
        from_digit? @actual[input]
      end

      def report(input)
        {
          value: value?(input),
          forced: forced?(input),
          forced_value: forced_value?(input),
          actual: actual?(input)
        }
      end

      def value_string
        @value[1..]
      end

      def forced_string
        @forced[1..]
      end

      def forced_value_string
        @forced[1..]
      end

      def actual_string
        @actual[1..]
      end

      protected

      def check_input(input)
        raise ArgumentError, "Input index #{input} must be in the range 1-#{@size}" if input < 1 || input > @size
      end

      def from_digit?(input)
        input == '1'
      end

      def to_digit(input)
        input ? '1' : '0'
      end

      def update_actual(input)
        @actual[input] = if from_digit? @forced[input]
                           @forced_value[input]
                         else
                           @value[input]
                         end
      end

      def report_change(input)
        before = @actual[input]
        yield
        return unless @actual[input] != before

        from_digit? @actual[input]
      end
    end
  end
end
