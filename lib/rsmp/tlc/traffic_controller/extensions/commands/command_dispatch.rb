module RSMP
  module TLC
    module TrafficControllerExtensions
      module Commands
        module CommandDispatch
          def handle_command(command_code, arg, options = {})
            case command_code
            when 'M0001', 'M0002', 'M0003', 'M0004', 'M0005', 'M0006', 'M0007',
                 'M0012', 'M0013', 'M0014', 'M0015', 'M0016', 'M0017', 'M0018',
                 'M0019', 'M0020', 'M0021', 'M0022', 'M0023',
                 'M0103', 'M0104'

              send("handle_#{command_code.downcase}", arg, options)
            else
              raise UnknownCommand, "Unknown command #{command_code}"
            end
          end
        end
      end
    end
  end
end
