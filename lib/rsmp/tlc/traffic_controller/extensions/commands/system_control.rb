module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        module SystemControl
          def handle_m0004(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            log 'Sheduling restart of TLC', level: :info
            @node.defer :restart
          end

          def handle_m0012(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
          end

          def handle_m0015(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
          end

          def handle_m0016(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
          end

          def handle_m0020(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
          end

          def handle_m0021(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
          end

          def handle_m0022(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            id = arg['requestId']
            type = arg['type']
            priority = @signal_priorities.find { |p| p.id == id }
            handler = {
              'new' => method(:create_priority_request),
              'update' => method(:update_priority_request),
              'cancel' => method(:cancel_priority_request)
            }[type]

            raise MessageRejected, "Unknown type #{type}" unless handler

            handler.call(arg, priority)
          end

          def handle_m0023(arg, _options = {})
            @node.verify_security_code 2, arg['securityCode']
            timeout = arg['status'].to_i
            unless (0..65_535).cover?(timeout)
              raise RSMP::MessageRejected,
                    "Timeout must be in the range 0-65535, got #{timeout}"
            end

            if timeout.zero?
              log 'Dynamic bands timeout disabled', level: :info
            else
              log "Dynamic bands timeout set to #{timeout}min", level: :info
            end
            @dynamic_bands_timeout = timeout
          end

          def handle_m0103(arg, _options = {})
            level = { 'Level1' => 1, 'Level2' => 2 }[arg['status']]
            @node.change_security_code level, arg['oldSecurityCode'], arg['newSecurityCode']
          end

          def handle_m0104(arg, _options = {})
            @node.verify_security_code 1, arg['securityCode']
            time = Time.new(
              arg['year'],
              arg['month'],
              arg['day'],
              arg['hour'],
              arg['minute'],
              arg['second'],
              'UTC'
            )
            clock.set time
            log "Clock set to #{time}, (adjustment is #{clock.adjustment}s)", level: :info
          end

          def create_priority_request(arg, existing_priority)
            id = arg['requestId']
            raise MessageRejected, "Priority Request #{id} already exists" if existing_priority

            signal_group = node.find_component arg['signalGroupId'] if arg['signalGroupId']

            @signal_priorities << SignalPriority.new(
              node: self,
              id: id,
              level: arg['level'],
              eta: arg['eta'],
              vehicle_type: arg['vehicleType']
            )
            log "Priority request #{id} for signal group #{signal_group.c_id} received.", level: :info
          end

          def update_priority_request(arg, priority)
            id = arg['requestId']
            raise MessageRejected, "Cannot update priority request #{id}, not found" unless priority

            log "Updating Priority Request #{id}", level: :info
          end

          def cancel_priority_request(arg, priority)
            id = arg['requestId']
            raise MessageRejected, "Cannot cancel priority request #{id}, not found" unless priority

            priority.cancel
            log "Priority request with id #{id} cancelled.", level: :info
          end
        end
      end
    end
  end
end
