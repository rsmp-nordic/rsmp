require 'rubygems'

module RSMP
  # Represents a connection to a remote site or supervisor.
  # Provides common connection lifecycle and message handling.
  class Proxy
    WRAPPING_DELIMITER = "\f".freeze

    include Logging
    include Distributor
    include Task
    include Modules::State
    include Modules::Watchdogs
    include Modules::Acknowledgements
    include Modules::Send
    include Modules::Receive
    include Modules::Versions
    include Modules::Tasks

    attr_reader :state, :archive, :connection_info, :sxls, :accepted_sxls, :rejected_sxls,
                :collector, :ip, :port, :node, :core_version

    def initialize(options)
      @node = options[:node]
      options[:logger] = @node&.logger unless options[:logger] # default to node logger
      initialize_logging options
      initialize_distributor
      initialize_task
      setup options
      clear
      @state = :disconnected
      @state_condition = Async::Notification.new
    end

    def inspect
      "#<#{self.class.name}:#{object_id} state:#{state}}>"
    end

    def now
      node.now
    end

    # Connection lifecycle methods

    def disconnect; end

    # wait for the reader task to complete,
    # which is not expected to happen before the connection is closed
    def wait_for_reader
      @reader&.wait
    end

    # close connection, but keep our main task running so we can reconnect
    def close
      log 'Closing connection', level: :warning
      close_stream
      close_socket
      stop_reader
      self.state = :disconnected
      distribute_error DisconnectError.new('Connection was closed')

      # stop timer
      # as we're running inside the timer, code after stop_timer() will not be called,
      # unless it's in the ensure block
      stop_timer
    end

    def stop_subtasks
      stop_timer
      stop_reader
      clear
      super
    end

    def stop_timer
      @timer&.stop
    ensure
      @timer = nil
    end

    def stop_reader
      @reader&.stop
    ensure
      @reader = nil
    end

    def close_stream
      @stream&.close
    ensure
      @stream = nil
    end

    def close_socket
      @socket&.close
    ensure
      @socket = nil
    end

    def stop_task
      close
      super
    end

    # State management methods

    def ready?
      @state == :ready
    end

    def connected?
      @state == :connected || @state == :ready
    end

    def disconnected?
      @state == :disconnected
    end

    # change our state
    def state=(state)
      return if state == @state

      @state = state
      state_changed
    end

    # the state changed
    # override to to things like notifications
    def state_changed
      @state_condition.signal @state
    end

    def clear
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @watchdog_started = false
      @version_determined = false
      @ingoing_acknowledged = {}
      @outgoing_acknowledged = {}
      @latest_watchdog_send_at = nil
      @component_list_received = false
      @outgoing_watchdog_acknowledged = false

      @acknowledgements = {}
      @acknowledgement_condition = Async::Notification.new
    end

    # revive after a reconnect
    def revive(options)
      setup options
    end

    def setup(options)
      @settings = options[:settings]
      @socket = options[:socket]
      @stream = options[:stream]
      @protocol = options[:protocol]
      @ip = options[:ip]
      @port = options[:port]
      @connection_info = options[:info]
      @sxls = []
      @accepted_sxls = []
      @rejected_sxls = []
      @receive_alarms = true
      @site_settings = nil # can't pick until we know the site id
      return unless options[:collect]

      @collector = RSMP::Collector.new self, options[:collect]
      @collector.start
    end

    def clock
      @node.clock
    end

    def receive_error(error, options = {})
      @node.receive_error error, options
    end

    def log(str, options = {})
      super(str, options.merge(ip: @ip, port: @port, site_id: @site_id))
    end

    def schemas
      schemas = { core: RSMP::Schema.latest_core_version } # use latest core
      schemas[:core] = core_version if core_version
      accepted_sxls.each do |sxl|
        schemas[sxl['name'].to_sym] = RSMP::Schema.sanitize_version(sxl['version'].to_s)
      end
      schemas
    end

    def receive_alarms?
      @receive_alarms != false
    end

    def primary_sxl
      (accepted_sxls.first || sxls.first)
    end

    def sxl
      primary_sxl && primary_sxl['name']
    end

    def sxl_version
      primary_sxl && primary_sxl['version']
    end

    def author
      @node.site_id
    end

    # Use Gem class to check version requirement
    # Requirement must be a string like '1.1', '>=1.0.3' or '<2.1.4',
    # or list of strings, like ['<=1.4','<1.5']
    def self.version_meets_requirement?(version, requirement)
      Modules::Versions.version_meets_requirement?(version, requirement)
    end
  end
end
