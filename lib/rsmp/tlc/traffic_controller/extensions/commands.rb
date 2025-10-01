require_relative 'commands/command_dispatch'
require_relative 'commands/mode_control'
require_relative 'commands/input_logic'
require_relative 'commands/input_management'
require_relative 'commands/plan_management'
require_relative 'commands/system_control'
require_relative 'commands/emergency_control'

module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        include CommandDispatch
        include ModeControl
        include InputLogic
        include InputManagement
        include PlanManagement
        include SystemControl
        include EmergencyControl
      end
    end
  end
end
