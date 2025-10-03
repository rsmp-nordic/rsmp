# frozen_string_literal: true

module RSMP
  module TLC
    module Modules
      # State predicate methods
      module State
        def dark?
          @function_position == 'Dark'
        end

        def yellow_flash?
          @function_position == 'YellowFlash'
        end

        def normal_control?
          @function_position == 'NormalControl'
        end
      end
    end
  end
end
