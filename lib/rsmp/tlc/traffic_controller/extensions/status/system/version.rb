module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module System
          module Version
            TIME_COMPONENT_FORMATTERS = {
              'year' => ->(time) { time.year.to_s.rjust(4, '0') },
              'month' => ->(time) { time.month.to_s.rjust(2, '0') },
              'day' => ->(time) { time.day.to_s.rjust(2, '0') },
              'hour' => ->(time) { time.hour.to_s.rjust(2, '0') },
              'minute' => ->(time) { time.min.to_s.rjust(2, '0') },
              'second' => ->(time) { time.sec.to_s.rjust(2, '0') }
            }.freeze

            def handle_s0095(_status_code, status_name = nil, _options = {})
              case status_name
              when 'status'
                TrafficControllerSite.make_status RSMP::VERSION
              end
            end

            def handle_s0096(_status_code, status_name = nil, _options = {})
              formatter = TIME_COMPONENT_FORMATTERS[status_name]
              return unless formatter

              TrafficControllerSite.make_status formatter.call(clock.now)
            end

            def handle_s0097(_status_code, status_name = nil, _options = {})
              case status_name
              when 'checksum'
                TrafficControllerSite.make_status '1'
              when 'timestamp'
                now = clock.to_s
                TrafficControllerSite.make_status now
              end
            end

            def handle_s0098(_status_code, status_name = nil, _options = {})
              settings = node.site_settings.slice('components', 'signal_plans', 'inputs', 'startup_sequence')
              json = JSON.generate(settings)
              case status_name
              when 'config'
                TrafficControllerSite.make_status json
              when 'timestamp'
                now = clock.to_s
                TrafficControllerSite.make_status now
              when 'version'
                TrafficControllerSite.make_status Digest::MD5.hexdigest(json)
              end
            end
          end
        end
      end
    end
  end
end
