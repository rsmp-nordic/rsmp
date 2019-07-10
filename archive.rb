# Archive of log items, which can be messages or info items.
# All items are timestamped, and stored chronologically.

module RSMP
  class Archive
    attr_reader :items
    attr_accessor :probes

    def initialize
      @items = []
      @mutex = Mutex.new
      @probes = ProbeCollection.new
    end

    def self.prepare_item item
      raise ArgumentError unless item.is_a? Hash
    
      now_obj = RSMP.now_object
      now_str = RSMP.now_string(now_obj)

      cleaned = item.select { |k,v| [:level,:ip,:site_id,:str,:message,:exception].include? k }
      cleaned[:timestamp] = now_obj
      cleaned[:direction] = item[:message].direction if item[:message]
      
      cleaned
    end

    def current_index
      @items.size
    end

    def add item
      @mutex.synchronize do
        item[:index] = @items.size
        @items << item
        probe item
      end
    end

    def capture options
      probe = RSMP::Probe.new self
      probe.capture options
    end

    private

    def probe item
      @probes.process item
    end

    def find options, &block
      # search backwards from newest to older, stopping once messages
      # are older that options[:earliest]
      out = []
      @items.reverse_each do |item|
        break if options[:earliest] && item[:timestamp] < options[:earliest]
        next if options[:type] && (item[:message] == nil || (item[:message].type != options[:type]))
        next if options[:with_message] && !(item[:direction] && item[:message])
        next if block_given? && block.call != true
        out.unshift item
      end
      out
    end
  end

end