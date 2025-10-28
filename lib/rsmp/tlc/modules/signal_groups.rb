module RSMP
  module TLC
    module Modules
      # Signal groups and signal priority management
      # Handles signal group status and priority requests
      module SignalGroups
        def add_signal_group(group)
          @signal_groups << group
        end

        def signal_priority_changed(priority, state); end

        # remove all stale priority requests
        def prune_priorities
          @signal_priorities.delete_if(&:prune?)
        end

        def priority_list
          @signal_priorities.map do |priority|
            {
              'r' => priority.id,
              't' => RSMP::Clock.to_s(priority.updated),
              's' => priority.state
            }
          end
        end

        # M0022 - Signal priority request
        def handle_m0022(arg, _options = {})
          id = arg['requestId']
          type = arg['type']
          priority = find_signal_priority(id)

          case type
          when 'new'
            create_priority_request(id, priority, arg)
          when 'update'
            update_priority_request(id, priority)
          when 'cancel'
            cancel_priority_request(id, priority)
          else
            raise MessageRejected, "Unknown type #{type}"
          end
        end

        private

        def find_signal_priority(id)
          @signal_priorities.find { |priority| priority.id == id }
        end

        def create_priority_request(id, existing_priority, arg)
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

        def update_priority_request(id, priority)
          raise MessageRejected, "Cannot update priority request #{id}, not found" unless priority

          log "Updating Priority Request #{id}", level: :info
        end

        def cancel_priority_request(id, priority)
          raise MessageRejected, "Cannot cancel priority request #{id}, not found" unless priority

          priority.cancel
          log "Priority request with id #{id} cancelled.", level: :info
        end

        # S0001 - Signal group status
        def handle_s0001(_status_code, status_name = nil, _options = {})
          case status_name
          when 'signalgroupstatus'
            TrafficControllerSite.make_status format_signal_group_status
          when 'cyclecounter', 'basecyclecounter'
            TrafficControllerSite.make_status @cycle_counter.to_s
          when 'stage'
            TrafficControllerSite.make_status 0.to_s
          end
        end

        # S0017 - Number of signal groups
        def handle_s0017(_status_code, status_name = nil, _options = {})
          case status_name
          when 'number'
            TrafficControllerSite.make_status @signal_groups.size
          end
        end

        # S0033 - Signal priority status
        def handle_s0033(_status_code, status_name = nil, _options = {})
          case status_name
          when 'status'
            TrafficControllerSite.make_status priority_list
          end
        end
      end
    end
  end
end
