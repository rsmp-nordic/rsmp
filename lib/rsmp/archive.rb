# Archive of log items, which can be messages or info items.
# All items are timestamped, and stored chronologically.

module RSMP
  class Archive
    include Inspect

    attr_reader :items

    @@index = 0

    def initialize(max = 100)
      @items = []
      @max = max
    end

    def inspect
      "#<#{self.class.name}:#{object_id}, #{inspector(:@items)}>"
    end

    def self.prepare_item(item)
      raise ArgumentError unless item.is_a? Hash

      cleaned = item.slice(:author, :level, :ip, :port, :site_id, :component, :text, :message, :exception)
      cleaned[:timestamp] = Clock.now
      if item[:message]
        cleaned[:direction] = item[:message].direction
        cleaned[:component] = item[:message].attributes['cId']
      end

      cleaned
    end

    def self.increase_index
      @@index += 1
    end

    def self.current_index
      @@index
    end

    def by_level(levels)
      items.select { |item| levels.include? item[:level] }
    end

    def strings
      items.map { |item| item[:str] }
    end

    def add(item)
      item[:index] = RSMP::Archive.increase_index
      @items << item
      return unless @items.size > @max

      @items.shift
    end

    private

    def find(options, &block)
      # search backwards from newest to older, stopping once messages
      # are older that options[:earliest]
      out = []
      @items.reverse_each do |item|
        break if options[:earliest] && item[:timestamp] < options[:earliest]
        next if options[:level] && item[:level] != options[:level]
        next if options[:type] && (item[:message].nil? || (item[:message].type != options[:type]))
        next if options[:with_message] && !(item[:direction] && item[:message])
        next if block_given? && block.call != true

        out.unshift item
      end
      out
    end
  end
end
