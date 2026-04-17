require 'timecop'

describe RSMP::TLC::StartupSequence do
  let(:sequence) { %w[state1 state2 state3] }
  let(:startup_sequence) { subject.new(sequence) }

  with '#initialize' do
    it 'sets sequence' do
      expect(startup_sequence.sequence).to be == sequence
    end

    it 'starts inactive' do
      expect(startup_sequence.active?).to be == false
    end

    it 'has no position' do
      expect(startup_sequence.position).to be_nil
    end

    it 'has no initiated_at time' do
      expect(startup_sequence.initiated_at).to be_nil
    end

    it 'handles nil sequence' do
      seq = subject.new(nil)
      expect(seq.sequence).to be == []
    end
  end

  with '#start' do
    it 'activates the sequence' do
      startup_sequence.start
      expect(startup_sequence.active?).to be == true
    end

    it 'resets position' do
      startup_sequence.start
      expect(startup_sequence.position).to be_nil
    end

    it 'resets initiated_at' do
      startup_sequence.start
      expect(startup_sequence.initiated_at).to be_nil
    end
  end

  with '#stop' do
    def before_stop
      startup_sequence.start
    end

    it 'deactivates the sequence' do
      before_stop
      startup_sequence.stop
      expect(startup_sequence.active?).to be == false
    end

    it 'clears position' do
      before_stop
      startup_sequence.stop
      expect(startup_sequence.position).to be_nil
    end

    it 'clears initiated_at' do
      before_stop
      startup_sequence.stop
      expect(startup_sequence.initiated_at).to be_nil
    end
  end

  with '#current_state' do
    with 'when inactive' do
      it 'returns nil' do
        expect(startup_sequence.current_state).to be_nil
      end
    end

    with 'when active but not advanced' do
      it 'returns nil' do
        startup_sequence.start
        expect(startup_sequence.current_state).to be_nil
      end
    end

    with 'when active and advanced' do
      it 'returns first state' do
        startup_sequence.start
        Timecop.freeze(Time.now) do
          startup_sequence.advance
        end
        expect(startup_sequence.current_state).to be == 'state1'
      end
    end

    with 'when position is beyond sequence' do
      it 'returns nil' do
        startup_sequence.start
        Timecop.freeze(Time.now) do
          startup_sequence.advance
          Timecop.travel(sequence.size + 1) do
            startup_sequence.advance
          end
        end
        expect(startup_sequence.current_state).to be_nil
      end
    end
  end

  with '#advance' do
    with 'when inactive' do
      it 'does nothing' do
        startup_sequence.advance
        expect(startup_sequence.position).to be_nil
        expect(startup_sequence.initiated_at).to be_nil
      end
    end

    with 'when active' do
      it 'initializes position to 0 on first call' do
        startup_sequence.start
        Timecop.freeze(Time.now) do
          startup_sequence.advance
          expect(startup_sequence.position).to be == 0
        end
      end

      it 'sets initiated_at to next second on first call' do
        startup_sequence.start
        now = Time.now
        Timecop.freeze(now) do
          startup_sequence.advance
          expect(startup_sequence.initiated_at).to be == (now.to_i + 1)
        end
      end

      it 'increments position based on elapsed time' do
        startup_sequence.start
        Timecop.freeze(Time.now) do |now|
          startup_sequence.advance
          expect(startup_sequence.position).to be == 0

          Timecop.travel(now + 1) do
            startup_sequence.advance
            expect(startup_sequence.position).to be == 0
          end

          Timecop.travel(now + 2) do
            startup_sequence.advance
            expect(startup_sequence.position).to be == 1
          end

          Timecop.travel(now + 3) do
            startup_sequence.advance
            expect(startup_sequence.position).to be == 2
          end
        end
      end

      it 'stops when sequence is complete' do
        startup_sequence.start
        Timecop.freeze(Time.now) do |now|
          startup_sequence.advance

          Timecop.travel(now + sequence.size + 1) do
            startup_sequence.advance
            expect(startup_sequence.active?).to be == false
          end
        end
      end
    end
  end

  with '#complete?' do
    with 'when inactive' do
      it 'returns false' do
        expect(startup_sequence.complete?).to be == false
      end
    end

    with 'when active but not started' do
      it 'returns false' do
        startup_sequence.start
        expect(startup_sequence.complete?).to be == false
      end
    end

    with 'when position is within sequence' do
      it 'returns false' do
        startup_sequence.start
        Timecop.freeze(Time.now) do
          startup_sequence.advance
        end
        expect(startup_sequence.complete?).to be == false
      end
    end

    with 'when position reaches sequence size' do
      it 'stops automatically' do
        startup_sequence.start
        now = Time.now
        Timecop.freeze(now) do
          startup_sequence.advance
          expect(startup_sequence.active?).to be == true

          Timecop.freeze(now + sequence.size + 1) do
            startup_sequence.advance
            expect(startup_sequence.active?).to be == false
          end
        end
      end
    end
  end

  with 'empty sequence' do
    let(:empty_sequence) { subject.new([]) }

    it 'completes immediately on first advance' do
      empty_sequence.start
      Timecop.freeze(Time.now) do
        empty_sequence.advance
        expect(empty_sequence.active?).to be == false
      end
    end
  end
end
