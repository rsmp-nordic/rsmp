# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Display and output formatting
      module Display
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
          else # includes /^g$/ and any other values
            display_string.colorize(:red)
          end
        end

        def mode_indicators
          {
            0 => ['N', @function_position == 'NormalControl'],
            1 => ['Y', @function_position == 'YellowFlash'],
            2 => ['D', @function_position == 'Dark'],
            3 => ['B', @booting],
            4 => ['S', @startup_sequence_active],
            5 => ['M', @manual_control],
            6 => ['F', @fixed_time_control],
            7 => ['R', @all_red],
            8 => ['I', @isolated_control],
            9 => ['P', @police_key != 0]
          }
        end

        def format_mode_indicators
          modes = '.' * 10
          mode_indicators.each do |pos, (char, active)|
            modes[pos] = char if active
          end
          modes
        end

        def write_state_output(modes, plan, signal_states)
          # create folders if needed
          FileUtils.mkdir_p File.dirname(@live_output)

          # append a line with the current state to the file
          File.open @live_output, 'w' do |file|
            file.puts "#{modes}  #{plan.rjust(2)}  #{@cycle_counter.to_s.rjust(3)}  #{signal_states}\r"
          end
        end
      end
    end
  end
end
