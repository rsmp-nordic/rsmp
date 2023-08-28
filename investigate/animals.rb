# frozen_string_literal: true

require_relative 'app'

SPEED = 2

# Animal
class Animal < Worker
  def run
    log 'wake'
    loop do
      sleep rand(0..10) * 1.0/SPEED
      raise 'sleepy!' if rand(10).zero?
      log 'grrr' if rand(5).zero?
    end
  end

  def party
    log 'jump' if rand(5).zero?
  end

  def stop
    log 'zzz'
  end

  def failed(error)
    log error
  end
end

# Place
class Place < Worker
  def run
    log 'open'
    loop do
      sleep rand(0..10) * 1.0/SPEED
      raise 'late!' if rand(5).zero?
      if rand(3).zero?
        log 'party' 
        sub_workers.each(&:party)
      end
    end
  end

  def stop
    log 'close'
  end

  def failed(error)
    log error
  end
end
