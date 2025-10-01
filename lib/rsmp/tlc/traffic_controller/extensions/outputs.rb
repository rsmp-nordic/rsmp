module RSMP
  module TLC
    module TrafficControllerExtensions
      module Outputs
        def output_states
          return unless @live_output

          str = format_colored_signal_states
          modes = format_mode_indicators
          plan = "P#{@plan}"

          write_state_output(modes, plan, str)
        end

        def format_signal_group_status
          @signal_groups.map(&:state).join
        end

        private

        def format_colored_signal_states
          @signal_groups.map do |group|
            state = group.state
            s = "#{group.c_id}:#{state}"
            colorize_signal_state(s, state)
          end.join ' '
        end

        def colorize_signal_state(display_string, state)
          case state
          when /^[1-9]$/
            display_string.colorize(:green)
          when /^[NOPf]$/
            display_string.colorize(:yellow)
          when /^[ae]$/
            display_string.colorize(:light_black)
          else
            display_string.colorize(:red)
          end
        end

        def format_mode_indicators
          statuses = [
            ['N', normal_control?],
            ['Y', yellow_flash?],
            ['D', dark?],
            ['B', @booting],
            ['S', @startup_sequence_active],
            ['M', @manual_control],
            ['F', @fixed_time_control],
            ['R', @all_red],
            ['I', @isolated_control],
            ['P', @police_key != 0]
          ]

          modes = '.' * statuses.size
          statuses.each_with_index do |(label, active), index|
            modes[index] = label if active
          end
          modes
        end

        def write_state_output(modes, plan, signal_states)
          FileUtils.mkdir_p File.dirname(@live_output)

          File.open @live_output, 'w' do |file|
            file.puts "#{modes}  #{plan.rjust(2)}  #{@cycle_counter.to_s.rjust(3)}  #{signal_states}\r"
          end
        end
      end
    end
  end
end
