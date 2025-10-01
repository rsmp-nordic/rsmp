require_relative 'system/user'
require_relative 'system/version'
require_relative 'system/traffic'

module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module System
          include User
          include Version
          include Traffic
        end
      end
    end
  end
end
