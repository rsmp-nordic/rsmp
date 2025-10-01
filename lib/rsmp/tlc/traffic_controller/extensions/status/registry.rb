module RSMP
  module TLC
    module TrafficControllerExtensions
      module Status
        module Registry
          HANDLED_STATUS_CODES = %w[
            S0001 S0002 S0003 S0004 S0005 S0006 S0007
            S0008 S0009 S0010 S0011 S0012 S0013 S0014
            S0015 S0016 S0017 S0018 S0019 S0020 S0021
            S0022 S0023 S0024 S0026 S0027 S0028
            S0029 S0030 S0031 S0032 S0033 S0035
            S0091 S0092 S0095 S0096 S0097 S0098
            S0205 S0206 S0207 S0208
          ].freeze

          def get_status(code, name = nil, options = {})
            raise InvalidMessage, "unknown status code #{code}" unless HANDLED_STATUS_CODES.include?(code)

            send("handle_#{code.downcase}", code, name, options)
          end
        end
      end
    end
  end
end
