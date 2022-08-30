module RSMP
  module VMS
    # TrafficController is the main component of a TrafficControllerSite.
    # It handles all command and status for the main component,
    # and keeps track of signal plans, detector logics, inputs, etc. which do
    # not have dedicated components.
    class VMSController < Component
      attr_reader :text

      def initialize node:, id:, ntsOId: nil, xNId: nil
        super node: node, id: id, ntsOId: ntsOId, xNId: xNId, grouped: true
        @current_bitmap = nil
        @bitmaps = []
        reset
      end

      def reset
        @page_num = 0
      end

      def clock
        node.clock
      end

      def string_to_bool bool_str
        case bool_str
          when 'True'
            true
          when 'False'
            false
          else
            raise RSMP::MessageRejected.new "Invalid boolean '#{bool}', must be 'True' or 'False'"
        end
      end

      def bool_string_to_digit bool
        case bool
          when 'True'
            '1'
          when 'False'
            '0'
          else
            raise RSMP::MessageRejected.new "Invalid boolean '#{bool}', must be 'True' or 'False'"
        end
      end

      def bool_to_digit bool
        bool ?  '1' : '0'
      end

      def handle_command command_code, arg, options={}
        case command_code
        when 'M0001'
          return handle_m001 arg, options
        when 'M0102'
          return handle_m0102 arg, options
        else
          raise UnknownCommand.new "Unknown command #{command_code}"
        end
      end

      def handle_m0001 arg, options={}
        switch_bitmap arg['number'].to_i
      end

      def handle_m0102 arg, options={}
        store_bitmap arg['index'].to_i, arg['bitmap']
      end

      def store_bitmap i, bitmap
        if i<1 || i>255
          raise InvalidMessage.new "Index must be between 1 and 255, got #{i}"
        end
        @bitmaps[i] = bitmap
      end

      def switch_bitmap i
        if i<0 || i>255
          raise InvalidMessage.new "Index must be between 0 and 255, got #{i}"
        end
        @current_bitmap = i
      end

      def get_status code, name=nil, options={}
        case code
        when 'S0007'
          handle_s0101 code, name, options
        when 'S0101'
          handle_s0101 code, name, options
        when 'S0102'
          handle_s0102 code, name, options
        else
          raise InvalidMessage.new "unknown status code #{code}"
        end
      end

      def handle_s0007 status_code, status_name=nil, options={}
        case status_name
        when 'status'
          VMSSite.make_status ''
        end
      end
      def handle_s0101 status_code, status_name=nil, options={}
        case status_name
        when 'number'
          VMSSite.make_status @current_bitmap
        end
      end

      def handle_s0102 status_code, status_name=nil, options={}
        case status_name
        when 'bitmap'
          if @current_bitmap
            VMSSite.make_status @bitmaps[@current_bitmap]
          else
            VMSSite.make_status ''
          end
        end
      end
    end
  end
end