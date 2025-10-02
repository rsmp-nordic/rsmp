# A connection to a remote site or supervisor.
# Uses the Task module to handle asyncronous work, but adds
# the concept of a connection that can be connected or disconnected.

require 'rubygems'

module RSMP
  class Proxy
    WRAPPING_DELIMITER = "\f".freeze

    include Logging
    include Distributor
    include Inspect
    include Task
    include Modules::ConnectionManagement
    include Modules::StateManagement
    include Modules::Watchdog
    include Modules::Acknowledgements
    include Modules::MessageSending
    include Modules::MessageProcessing
    include Modules::VersionHandling
    include Modules::Tasks

    attr_reader :state, :archive, :connection_info, :sxl, :collector, :ip, :port, :node, :core_version

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
      @sxl = nil
      @site_settings = nil # can't pick until we know the site id
      return unless options[:collect]

      @collector = RSMP::Collector.new self, options[:collect]
      @collector.start
    end

    def inspect
      "#<#{self.class.name}:#{object_id}, #{inspector(
        :@acknowledgements, :@settings, :@site_settings
      )}>"
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
      schemas[sxl] = RSMP::Schema.sanitize_version(sxl_version.to_s) if sxl && sxl_version
      schemas
    end

    def author
      @node.site_id
    end

    # Use Gem class to check version requirement
    # Requirement must be a string like '1.1', '>=1.0.3' or '<2.1.4',
    # or list of strings, like ['<=1.4','<1.5']
    def self.version_meets_requirement?(version, requirement)
      Modules::VersionHandling.version_meets_requirement?(version, requirement)
    end
  end
end
