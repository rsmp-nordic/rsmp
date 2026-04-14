module RSMP
  module TLC
    module Proxy
      # Command methods for operational control of a remote TLC.
      # Covers functional position, emergency routes, I/O modes, signal group orders, and system settings.
      module Detectors
        # M0008 — Force detector logic to a given mode and status.
        # component_id must refer to the detector logic component, not main.
        def force_detector_logic(component_id, status:, mode:, within: nil)
          validate_ready 'force detector logic'

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0008',
            'cO' => 'setForceDetectorLogic',
            'n' => 'status',
            'v' => status.to_s
          }, {
            'cCI' => 'M0008',
            'cO' => 'setForceDetectorLogic',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }, {
            'cCI' => 'M0008',
            'cO' => 'setForceDetectorLogic',
            'n' => 'mode',
            'v' => mode.to_s
          }]
          send_command_with_confirm component_id, command_list, "force detector logic #{component_id}", nil, within: within
        end

        # M0021 — Set the trigger level for traffic counting.
        def set_trigger_level(status, within: nil)
          validate_ready 'set trigger level'
          raise 'TLC main component not found' unless main

          security_code = security_code_for(2)

          command_list = [{
            'cCI' => 'M0021',
            'cO' => 'setLevel',
            'n' => 'status',
            'v' => status.to_s
          }, {
            'cCI' => 'M0021',
            'cO' => 'setLevel',
            'n' => 'securityCode',
            'v' => security_code.to_s
          }]
          send_command_with_confirm main.c_id, command_list, "trigger level #{status}", nil, within: within
        end
      end
    end
  end
end
