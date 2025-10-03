# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Startup sequence management
      module StartupSequence
        def startup_state
          return unless @startup_sequence_active
          return unless @startup_sequence_pos

          @startup_sequence[@startup_sequence_pos]
        end

        def initiate_startup_sequence
          log 'Initiating startup sequence', level: :info
          reset_modes
          @startup_sequence_active = true
          @startup_sequence_initiated_at = nil
          @startup_sequence_pos = nil
        end

        def end_startup_sequence
          @startup_sequence_active = false
          @startup_sequence_initiated_at = nil
          @startup_sequence_pos = nil
        end

        def move_startup_sequence
          if @startup_sequence_initiated_at.nil?
            @startup_sequence_initiated_at = Time.now.to_i + 1
            @startup_sequence_pos = 0
          else
            @startup_sequence_pos = Time.now.to_i - @startup_sequence_initiated_at
          end
          return unless @startup_sequence_pos >= @startup_sequence.size

          end_startup_sequence
        end
      end
    end
  end
end
