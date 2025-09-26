require_relative 'status/registry'
require_relative 'status/signal'
require_relative 'status/control'
require_relative 'status/plan'
require_relative 'status/inputs'
require_relative 'status/system'

module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        include Registry
        include Signal
        include Control
        include Plan
        include Inputs
        include System
      end
    end
  end
end
