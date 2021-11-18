module RSMP
  module TLC
    # TrafficController is the main component of a TrafficControllerSite.
    # It handles all command and status for the main component,
    # and keeps track of signal plans, detector logics, inputs, etc. which do
    # not have dedicated components.
    class TrafficController < Component
      attr_reader :pos, :cycle_time, :plan

      def initialize node:, id:, cycle_time: 10, signal_plans:
        super node: node, id: id, grouped: true
        @signal_groups = []
        @detector_logics = []
        @plans = signal_plans
        @cycle_time = cycle_time
        @num_traffic_situations = 1
        @num_inputs = 8
        reset
      end

      def reset
        @pos = 0
        @plan = 0
        @dark_mode = false
        @yellow_flash = false
        @booting = false
        @control_mode = 'control'
        @police_key = 0
        @intersection = 0
        @is_starting = false
        @emergency_route = false
        @emergency_route_number = 0
        @traffic_situation = 0
        @manual_control = false
        @fixed_time_control = false
        @isolated_control = false
        @yellow_flash = false
        @all_red = false

        @inputs = '0'*@num_inputs
        @input_activations = '0'*@num_inputs
        @input_results = '0'*@num_inputs
      end

      def clock
        node.clock
      end

      def current_plan
        # TODO plan 0 should means use time table
        if @plans
          @plans[ plan ] || @plans.values.first
        else
          nil
        end
      end

      def add_signal_group group
        @signal_groups << group
      end

      def add_detector_logic logic
        @detector_logics << logic
      end

      def timer now
        # TODO
        # We should use a monotone timer, to avoid jumps
        # in case the user sets the system time
        pos = Time.now.to_i % @cycle_time
        if pos != @pos
          @pos = pos
          move pos
        end
      end

      def move pos
        @signal_groups.each do |group|
          group.move pos
        end
        #output_states
      end

      def output_states
        str = @signal_groups.map do |group|
          s = "#{group.c_id}:#{group.state}"
          if group.state =~ /^[1-9]$/
              s.colorize(:green)
          elsif group.state =~ /^[NOP]$/
            s.colorize(:yellow)
          elsif group.state =~ /^[a]$/
            s.colorize(color: :black)
          else
            s.colorize(:red)
          end
        end.join ' '
        plan = "P#{@plan}"
        print "#{plan.rjust(4)} #{pos.to_s.rjust(4)} #{str}\r"
      end

      def format_signal_group_status
        if @yellow_flash
          'c' * @signal_groups.size
        else
          @signal_groups.map { |group| group.state }.join
        end
      end

      def handle_command command_code, arg
        case command_code
        when 'M0001', 'M0002', 'M0003', 'M0004', 'M0005', 'M0006', 'M0007',
             'M0012', 'M0013', 'M0014', 'M0015', 'M0016', 'M0017', 'M0018',
             'M0019', 'M0020', 'M0021', 'M0022',
             'M0103', 'M0104'

          return send("handle_#{command_code.downcase}", arg)
        else
          raise UnknownCommand.new "Unknown command #{command_code}"
        end
      end

      def handle_m0001 arg
        @node.verify_security_code 2, arg['securityCode']
        switch_mode arg['status']
      end

      def handle_m0002 arg
        @node.verify_security_code 2, arg['securityCode']
        if TrafficControllerSite.from_rsmp_bool(arg['status'])
          switch_plan arg['timeplan']
        else
          switch_plan 0   # TODO use clock/calender
        end
      end

      def handle_m0003 arg
        @node.verify_security_code 2, arg['securityCode']
        @traffic_situation = arg['traficsituation'].to_i
      end

      def handle_m0004 arg
        @node.verify_security_code 2, arg['securityCode']
        # don't restart immeediately, since we need to first send command response
        # instead, defer an action, which will be handled by the TLC site
        log "Sheduling restart of TLC", level: :info
        @node.defer :restart
      end

      def handle_m0005 arg
        @node.verify_security_code 2, arg['securityCode']
        @emergency_route = (arg['status'] == 'True')
        @emergency_route_number = arg['emergencyroute'].to_i

        if @emergency_route
          log "Switching to emergency route #{@emergency_route_number}", level: :info
        else
          log "Switching off emergency route", level: :info
        end
      end

      def handle_m0006 arg
        @node.verify_security_code 2, arg['securityCode']
        input = arg['input'].to_i
        idx = input - 1
        return unless idx>=0 && input<@num_inputs # TODO should NotAck
        @input_activations[idx] = (arg['status']=='True' ? '1' : '0')
        result = @input_activations[idx]=='1' || @inputs[idx]=='1'
        @input_results[idx] = (result ? '1' : '0')
        if @input_activations[idx]
          log "Activate input #{idx}", level: :info
        else
          log "Deactivate input #{idx}", level: :info
        end
      end

      def handle_m0007 arg
        @node.verify_security_code 2, arg['securityCode']
        set_fixed_time_control arg['status']
      end

      def handle_m0012 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0013 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def find_plan plan_nr
        plan = @plans[plan_nr.to_i]
        raise InvalidMessage.new "unknown signal plan #{plan_nr}, known only [#{@plans.keys.join(',')}]" unless plan
        plan
      end

      def handle_m0014 arg
        @node.verify_security_code 2, arg['securityCode']
        plan = find_plan arg['plan']
        arg['status'].split(',').each do |item|
          matched = /(\d+)-(\d+)/.match item
          band = matched[1].to_i
          value = matched[2].to_i
          log "Set plan #{arg['plan']} dynamic band #{band} to #{value}", level: :info
          plan.set_band band, value
        end
      end

      def handle_m0015 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0016 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0017 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0018 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0019 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0020 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0021 arg
        @node.verify_security_code 2, arg['securityCode']
      end

      def handle_m0103 arg
        level = {'Level1'=>1,'Level2'=>2}[arg['status']]
        @node.change_security_code level, arg['oldSecurityCode'], arg['newSecurityCode']
      end

      def handle_m0104 arg
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
        @node.clock.set time
        log "Clock set to #{time}, (adjustment is #{@node.clock.adjustment}s)", level: :info
      end

      def set_input i, value
        return unless i>=0 && i<@num_inputs
        @inputs[i] = (arg['value'] ? '1' : '0')
      end
      
      def set_fixed_time_control status
        @fixed_time_control = status
      end

      def switch_plan plan
        plan_nr = plan.to_i
        if plan_nr == 0
          log "Switching to plan selection by time table", level: :info
        else
          plan = find_plan plan_nr
          log "Switching to plan #{plan_nr}", level: :info
        end
        @plan = plan_nr
      end

      def switch_mode mode
        log "Switching to mode #{mode}", level: :info
        case mode
        when 'NormalControl'
          @yellow_flash = false
          @dark_mode = false
        when 'YellowFlash'
          @yellow_flash = true
          @dark_mode = false
        when 'Dark'
          @yellow_flash = false
          @dark_mode = true
        end
        mode
      end

      def get_status code, name=nil
        case code
        when 'S0001', 'S0002', 'S0003', 'S0004', 'S0005', 'S0006', 'S0007',
             'S0008', 'S0009', 'S0010', 'S0011', 'S0012', 'S0013', 'S0014',
             'S0015', 'S0016', 'S0017', 'S0018', 'S0019', 'S0020', 'S0021',
             'S0022', 'S0023', 'S0024', 'S0026', 'S0027', 'S0028',
             'S0029', 'S0030', 'S0031',
             'S0091', 'S0092', 'S0095', 'S0096', 'S0097',
             'S0205', 'S0206', 'S0207', 'S0208'
          return send("handle_#{code.downcase}", code, name)
        else
          raise InvalidMessage.new "unknown status code #{code}"
        end
      end

      def handle_s0001 status_code, status_name=nil
        case status_name
        when 'signalgroupstatus'
          TrafficControllerSite.make_status format_signal_group_status
        when 'cyclecounter'
          TrafficControllerSite.make_status @pos.to_s
        when 'basecyclecounter'
          TrafficControllerSite.make_status @pos.to_s
        when 'stage'
          TrafficControllerSite.make_status 0.to_s
        end
      end

      def handle_s0002 status_code, status_name=nil
        case status_name
        when 'detectorlogicstatus'
          TrafficControllerSite.make_status @detector_logics.map { |dl| dl.value ? '1' : '0' }.join
        end
      end

      def handle_s0003 status_code, status_name=nil
        case status_name
        when 'inputstatus'
          TrafficControllerSite.make_status @input_results
        when 'extendedinputstatus'
          TrafficControllerSite.make_status 0.to_s
        end
      end

      def handle_s0004 status_code, status_name=nil
        case status_name
        when 'outputstatus'
          TrafficControllerSite.make_status 0
        when 'extendedoutputstatus'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0005 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status @is_starting
        end
      end

      def handle_s0006 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status @emergency_route
        when 'emergencystage'
          TrafficControllerSite.make_status @emergency_route_number
        end
      end

      def handle_s0007 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status !@dark_mode
        end
      end

      def handle_s0008 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @manual_control
        end
      end

      def handle_s0009 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @fixed_time_control
        end
      end

      def handle_s0010 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @isolated_control
        end
      end

      def handle_s0011 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @yellow_flash
        end
      end

      def handle_s0012 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @all_red
        end
      end

      def handle_s0013 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'status'
          TrafficControllerSite.make_status @police_key
        end
      end

      def handle_s0014 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status @plan
        end
      end

      def handle_s0015 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status @traffic_situation
        end
      end

      def handle_s0016 status_code, status_name=nil
        case status_name
        when 'number'
          TrafficControllerSite.make_status @detector_logics.size
        end
      end

      def handle_s0017 status_code, status_name=nil
        case status_name
        when 'number'
          TrafficControllerSite.make_status @signal_groups.size
        end
      end

      def handle_s0018 status_code, status_name=nil
        case status_name
        when 'number'
          TrafficControllerSite.make_status @plans.size
        end
      end

      def handle_s0019 status_code, status_name=nil
        case status_name
        when 'number'
          TrafficControllerSite.make_status @num_traffic_situations
        end
      end

      def handle_s0020 status_code, status_name=nil
        case status_name
        when 'intersection'
          TrafficControllerSite.make_status @intersection
        when 'controlmode'
          TrafficControllerSite.make_status @control_mode
        end
      end

      def handle_s0021 status_code, status_name=nil
        case status_name
        when 'detectorlogics'
          TrafficControllerSite.make_status @detector_logics.map { |logic| logic.forced=='True' ? '1' : '0'}.join
        end
      end

      def handle_s0022 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status @plans.keys.join(',')
        end
      end

      def handle_s0023 status_code, status_name=nil
        case status_name
        when 'status'
          dynamic_bands = @plans.map { |nr,plan| plan.dynamic_bands_string }
          str = dynamic_bands.compact.join(',')
          TrafficControllerSite.make_status str
        end
      end

      def handle_s0024 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status '1-0'
        end
      end

      def handle_s0026 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status '0-00'
        end
      end

      def handle_s0027 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status '00-00-00-00'
        end
      end

      def handle_s0028 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status '00-00'
        end
      end

      def handle_s0029 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status ''
        end
      end

      def handle_s0030 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status ''
        end
      end

      def handle_s0031 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status ''
        end
      end

      def handle_s0091 status_code, status_name=nil
        case status_name
        when 'user'
          TrafficControllerSite.make_status 'nobody'
        when 'status'
          TrafficControllerSite.make_status 'logout'
        end
      end

      def handle_s0092 status_code, status_name=nil
        case status_name
        when 'user'
          TrafficControllerSite.make_status 'nobody'
        when 'status'
          TrafficControllerSite.make_status 'logout'
        end
      end

      def handle_s0095 status_code, status_name=nil
        case status_name
        when 'status'
          TrafficControllerSite.make_status RSMP::VERSION
        end
      end

      def handle_s0096 status_code, status_name=nil
        now = clock.now
        case status_name
        when 'year'
          TrafficControllerSite.make_status now.year.to_s.rjust(4, "0")
        when 'month'
          TrafficControllerSite.make_status now.month.to_s.rjust(2, "0")
        when 'day'
          TrafficControllerSite.make_status now.day.to_s.rjust(2, "0")
        when 'hour'
          TrafficControllerSite.make_status now.hour.to_s.rjust(2, "0")
        when 'minute'
          TrafficControllerSite.make_status now.min.to_s.rjust(2, "0")
        when 'second'
          TrafficControllerSite.make_status now.sec.to_s.rjust(2, "0")
        end
      end

      def handle_s0097 status_code, status_name=nil
        case status_name
        when 'checksum'
          TrafficControllerSite.make_status '1'
        when 'timestamp'
          now = @node.clock.to_s
          TrafficControllerSite.make_status now
        end
      end

      def handle_s0205 status_code, status_name=nil
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'vehicles'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0206 status_code, status_name=nil
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'speed'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0207 status_code, status_name=nil
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'occupancy'
          TrafficControllerSite.make_status 0
        end
      end

      def handle_s0208 status_code, status_name=nil
        case status_name
        when 'start'
          TrafficControllerSite.make_status clock.to_s
        when 'P'
          TrafficControllerSite.make_status 0
        when 'PS'
          TrafficControllerSite.make_status 0
        when 'L'
          TrafficControllerSite.make_status 0
        when 'LS'
          TrafficControllerSite.make_status 0
        when 'B'
          TrafficControllerSite.make_status 0
        when 'SP'
          TrafficControllerSite.make_status 0
        when 'MC'
          TrafficControllerSite.make_status 0
        when 'C'
          TrafficControllerSite.make_status 0
        when 'F'
          TrafficControllerSite.make_status 0
        end
      end
    end
  end
end