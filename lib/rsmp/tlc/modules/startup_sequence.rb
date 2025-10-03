# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # Startup sequence management
      module StartupSequence
        def startup_state
          @startup_sequence.current_state
        end

        def initiate_startup_sequence
          log 'Initiating startup sequence', level: :info
          reset_modes
          @startup_sequence.start
        end

        def end_startup_sequence
          @startup_sequence.stop
        end
      end
    end
  end
end
