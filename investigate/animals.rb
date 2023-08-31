# frozen_string_literal: true

require_relative 'app'

SPEED = 2

class Worker
  module State
    attr_reader :state

    def initialize node
      super
      @state = initial_state
    end

    def initial_state
      ''
    end

    def log str
      return if str == @state
      was = @state
      @state = str
      super( "#{was.to_s.ljust(7)} => #{str}" )
    end
  end
end    

# Animal
class Animal < Worker
  include State

  def initial_state
    'zzz'
  end

  def run
    sleep 2*rand(0..10) * 1.0/SPEED
    log 'wake'
    loop do
      sleep rand(0..10) * 1.0/SPEED
      raise 'sleepy!' if rand(10).zero?
      log 'grrr' if rand(5).zero?
    end
  end

  def party
    if rand(3).zero?
      if @state == 'zzz'
        log 'mmm'
      else
        log 'jump'
      end
    end
  end

  def stop
    log 'zzz'
  end

  def failed(error)
    log error
    sleep rand(0..10) * 1.0/SPEED
  end
end

# Place
class Place < Worker
  include State

  def initial_state
    'closed'
  end

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
    sleep rand(0..10) * 1.0/SPEED
  end
end
