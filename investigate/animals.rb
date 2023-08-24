# frozen_string_literal: true

require_relative 'app'

# Animal
class Animal < Worker
  def run
    log 'wake'
    loop do
      sleep rand(0..10) * 1
      raise 'sleepy!' if rand(10).zero?
      log 'grrr' if rand(2).zero?
    end
  end

  def party
      raise 'dance' if rand(10).zero?
  end

  def stop
    log 'zzz'
  end

  def fail(error)
    log error
  end
end

# Place
class Place < Worker
  def run
    log 'open'
    loop do
      sleep rand(0..10) * 1
      raise 'late!' if rand(5).zero?
      if rand(5).zero?
        log 'party' 
        #@node.nodes.values.each(&:party)
      end
    end
  end

  def stop
    log 'close'
  end

  def fail(error)
    log error
  end
end
