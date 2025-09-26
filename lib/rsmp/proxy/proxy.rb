# A connection to a remote site or supervisor.
# Uses the Task module to handle asyncronous work, but adds
# the concept of a connection that can be connected or disconnected.

require 'rubygems'
require_relative 'connection'
require_relative 'reader'
require_relative 'watchdog'
require_relative 'utilities'
require_relative 'messaging'

module RSMP
  class Proxy
    WRAPPING_DELIMITER = "\f".freeze

    include Logging
    include Distributor
    include Inspect
    include Task

    include ProxyExtensions::ConnectionManagement
    include ProxyExtensions::Reader
    include ProxyExtensions::Watchdog
    include ProxyExtensions::Utilities
    include ProxyExtensions::OutgoingMessages
    include ProxyExtensions::IncomingMessages
    include ProxyExtensions::IncomingHandlers
    include ProxyExtensions::Acknowledgements
    include ProxyExtensions::VersionNegotiation
    include ProxyExtensions::StateSynchronization

    attr_reader :state, :archive, :connection_info, :sxl, :collector, :ip, :port, :node, :core_version

    # Use Gem class to check version requirement
    # Requirement must be a string like '1.1', '>=1.0.3' or '<2.1.4',
    # or list of strings, like ['<=1.4','<1.5']
    def self.version_meets_requirement?(version, requirement)
      Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(version))
    end

    def initialize(options)
      @node = options[:node]
      initialize_logging options
      initialize_distributor
      initialize_task
      setup options
      clear
      @state = :disconnected
      @state_condition = Async::Notification.new
    end

    def now
      node.now
    end

    def disconnect; end

    def wait_for_reader
      @reader&.wait
    end

    def change_state(state)
      return if state == @state

      @state = state
      puts "[DEBUG] #{self.class.name} state -> #{@state}" if ENV['RSMP_DEBUG_STATES']
      state_changed
    end

    def state_changed
      @state_condition.signal @state
    end

    def revive(options)
      setup options
    end

    def inspect
      "#<#{self.class.name}:#{object_id}, #{inspector(
        :@acknowledgements, :@settings, :@site_settings
      )}>"
    end

    def clock
      @node.clock
    end

    def ready?
      @state == :ready
    end

    def connected?
      @state == :connected || @state == :ready
    end

    def disconnected?
      @state == :disconnected
    end

    private

    def setup(options)
      @settings = options[:settings]
      @socket = options[:socket]
      @stream = options[:stream]
      @protocol = options[:protocol]
      @ip = options[:ip]
      @port = options[:port]
      @connection_info = options[:info]
      @sxl = nil
      @site_settings = nil # can't pick until we know the site id
      return unless options[:collect]

      @collector = RSMP::Collector.new self, options[:collect]
      @collector.start
    end

    def clear
      @awaiting_acknowledgement = {}
      @latest_watchdog_received = nil
      @watchdog_started = false
      @version_determined = false
      @ingoing_acknowledged = {}
      @outgoing_acknowledged = {}
      @latest_watchdog_send_at = nil

      @acknowledgements = {}
      @acknowledgement_condition = Async::Notification.new
    end
  end
end
