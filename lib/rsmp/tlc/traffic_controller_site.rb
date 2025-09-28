module RSMP
  module TLC
    # Simulates a Traffic Light Controller Site
    class TrafficControllerSite < Site
      attr_accessor :main, :signal_plans

      def initialize(options = {})
        # setup options before calling super initializer,
        # since build of components depend on options
        @sxl = 'traffic_light_controller'
        @security_codes = options[:site_settings]['security_codes']
        @interval = options[:site_settings].dig('intervals', 'timer') || 1
        @startup_sequence = options[:site_settings]['startup_sequence'] || 'efg'
        build_plans options[:site_settings]['signal_plans']

        super

        return if main

        raise ConfigurationError, 'TLC must have a main component'
      end

      def site_type_name
        'TLC'
      end

      def start
        super
        start_tlc_timer
        main.initiate_startup_sequence
      end

      def stop_subtasks
        stop_tlc_timer
        super
      end

      def build_plans(signal_plans)
        @signal_plans = {}
        return unless signal_plans

        signal_plans.each_pair do |id, settings|
          states = nil
          cycle_time = settings['cycle_time']
          states = settings['states'] if settings
          dynamic_bands = settings['dynamic_bands'] if settings

          @signal_plans[id.to_i] =
            SignalPlan.new(nr: id.to_i, cycle_time: cycle_time, states: states, dynamic_bands: dynamic_bands)
        end
      end

      def get_plan(_group_id, _plan_nr)
        'NN1BB1'
      end

      def build_component(id:, type:, settings: {})
        case type
        when 'main'
          TrafficController.new node: self,
                                id: id,
                                ntsoid: settings['ntsOId'],
                                xnid: settings['xNId'],
                                startup_sequence: @startup_sequence,
                                signal_plans: @signal_plans,
                                live_output: @site_settings['live_output'],
                                inputs: @site_settings['inputs']
        when 'signal_group'
          group = SignalGroup.new node: self, id: id
          main.add_signal_group group
          group
        when 'detector_logic'
          logic = DetectorLogic.new node: self, id: id
          main.add_detector_logic logic
          logic
        end
      end

      def start_tlc_timer
        task_name = 'tlc timer'
        log "Starting #{task_name} with interval #{@interval} seconds", level: :debug

        @timer = @task.async do |task|
          task.annotate task_name
          run_tlc_timer task
        end
      end

      def run_tlc_timer(task)
        next_time = Time.now.to_f
        loop do
          timer(@clock.now)
        rescue StandardError => e
          distribute_error e, level: :internal
        ensure
          # adjust sleep duration to avoid drift. so wake up always happens on the
          # same fractional second.
          # note that Time.now is not monotonic. If the clock is changed,
          # either manaully or via NTP, the sleep interval might jump.
          # an alternative is to use ::Process.clock_gettime(::Process::CLOCK_MONOTONIC),
          # to get the current time. this ensures a constant interval, but
          # if the clock is changed, the wake up would then happen on a different
          # fractional second
          next_time += @interval
          duration = next_time - Time.now.to_f
          task.sleep duration
        end
      end

      def stop_tlc_timer
        return unless @timer

        @timer.stop
        @timer = nil
      end

      def timer(now)
        return unless main

        main.timer now
      end

      def verify_security_code(level, code)
        raise ArgumentError, "Level must be 1-2, got #{level}" unless (1..2).include?(level)
        return unless @security_codes[level] != code

        raise MessageRejected, "Wrong security code for level #{level}"
      end

      def change_security_code(level, old_code, new_code)
        verify_security_code level, old_code
        @security_codes[level] = new_code
      end

      def self.to_rmsp_bool(bool)
        if bool
          'True'
        else
          'False'
        end
      end

      def self.from_rsmp_bool?(str)
        str == 'True'
      end

      def self.make_status(value, quality = 'recent')
        case value
        when true, false
          [to_rmsp_bool(value), quality]
        else
          [value, quality]
        end
      end

      def do_deferred(key, _item = nil)
        case key
        when :restart
          log 'Restarting TLC', level: :info
          restart
        end
      end
    end
  end
end
