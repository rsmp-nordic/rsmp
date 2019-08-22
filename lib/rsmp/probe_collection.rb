# Collection of probes

module RSMP
  class ProbeCollection

    def initialize
      @probes = []
    end

    def add probe
      raise ArgumentError unless probe
      @probes << probe
    end

    def remove probe
      raise ArgumentError unless probe
      @probes.delete probe
    end

    def process item
      @probes.each { |probe| probe.process item }
    end

    def clear
      @probes.each { |probe| probe.clear }
    end
  end
end
