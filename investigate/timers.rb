require_relative 'jobs'

class Timer < Child
  def action
    loop do
      sleep rand(10) * 0.01
      log 'tick'
      raise 'oh no!' if rand(3) == 0
    end
  end
end

class App < Supervisor
  @@blueprint = {
    timer_1: { class: Timer, strategy: :all_for_one },
    timer_2: { class: Timer, strategy: :one_for_one }
  }

  def action
    super
    # sleep rand(3); raise 'major issues'
  end
end

begin
  Async do
    app = App.new.start
  end
rescue Interrupt
  puts
end
