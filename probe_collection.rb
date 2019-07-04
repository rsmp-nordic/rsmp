# Collection of probes

module RSMP
  class ProbeCollection

    def initialize
      @probes = []
      @mutex = Mutex.new
    end

    def add probe
      @mutex.synchronize do
        @probes << probe
      end
    end

    def remove probe
      @mutex.synchronize do
        @probes.delete probe
      end
    end

    def process item
      @mutex.synchronize do
        @probes.each { |probe| probe.process item }
      end
    end

    def clear
      @mutex.synchronize do
        @probes.each { |probe| probe.clear }
      end
    end
  end
end
