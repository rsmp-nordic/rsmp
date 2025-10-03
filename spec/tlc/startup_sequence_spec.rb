require 'timecop'

RSpec.describe RSMP::TLC::StartupSequence do
  let(:sequence) { %w[state1 state2 state3] }
  let(:startup_sequence) { described_class.new(sequence) }

  describe '#initialize' do
    it 'sets sequence' do
      expect(startup_sequence.sequence).to eq(sequence)
    end

    it 'starts inactive' do
      expect(startup_sequence.active?).to be(false)
    end

    it 'has no position' do
      expect(startup_sequence.position).to be_nil
    end

    it 'has no initiated_at time' do
      expect(startup_sequence.initiated_at).to be_nil
    end

    it 'handles nil sequence' do
      seq = described_class.new(nil)
      expect(seq.sequence).to eq([])
    end
  end

  describe '#start' do
    it 'activates the sequence' do
      startup_sequence.start
      expect(startup_sequence.active?).to be(true)
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

  describe '#stop' do
    before do
      startup_sequence.start
    end

    it 'deactivates the sequence' do
      startup_sequence.stop
      expect(startup_sequence.active?).to be(false)
    end

    it 'clears position' do
      startup_sequence.stop
      expect(startup_sequence.position).to be_nil
    end

    it 'clears initiated_at' do
      startup_sequence.stop
      expect(startup_sequence.initiated_at).to be_nil
    end
  end

  describe '#current_state' do
    context 'when inactive' do
      it 'returns nil' do
        expect(startup_sequence.current_state).to be_nil
      end
    end

    context 'when active but not advanced' do
      before do
        startup_sequence.start
      end

      it 'returns nil' do
        expect(startup_sequence.current_state).to be_nil
      end
    end

    context 'when active and advanced' do
      before do
        startup_sequence.start
        Timecop.freeze(Time.now) do
          startup_sequence.advance
        end
      end

      it 'returns first state' do
        expect(startup_sequence.current_state).to eq('state1')
      end
    end

    context 'when position is beyond sequence' do
      before do
        startup_sequence.start
        Timecop.freeze(Time.now) do
          startup_sequence.advance
          # Simulate time passing beyond sequence length
          Timecop.travel(sequence.size + 1) do
            startup_sequence.advance
          end
        end
      end

      it 'returns nil' do
        expect(startup_sequence.current_state).to be_nil
      end
    end
  end

  describe '#advance' do
    context 'when inactive' do
      it 'does nothing' do
        startup_sequence.advance
        expect(startup_sequence.position).to be_nil
        expect(startup_sequence.initiated_at).to be_nil
      end
    end

    context 'when active' do
      before do
        startup_sequence.start
      end

      it 'initializes position to 0 on first call' do
        Timecop.freeze(Time.now) do
          startup_sequence.advance
          expect(startup_sequence.position).to eq(0)
        end
      end

      it 'sets initiated_at to next second on first call' do
        now = Time.now
        Timecop.freeze(now) do
          startup_sequence.advance
          expect(startup_sequence.initiated_at).to eq(now.to_i + 1)
        end
      end

      it 'increments position based on elapsed time' do
        Timecop.freeze(Time.now) do |now|
          startup_sequence.advance
          expect(startup_sequence.position).to eq(0)

          Timecop.travel(now + 1) do
            startup_sequence.advance
            expect(startup_sequence.position).to eq(0)
          end

          Timecop.travel(now + 2) do
            startup_sequence.advance
            expect(startup_sequence.position).to eq(1)
          end

          Timecop.travel(now + 3) do
            startup_sequence.advance
            expect(startup_sequence.position).to eq(2)
          end
        end
      end

      it 'stops when sequence is complete' do
        Timecop.freeze(Time.now) do |now|
          startup_sequence.advance

          Timecop.travel(now + sequence.size + 1) do
            startup_sequence.advance
            expect(startup_sequence.active?).to be(false)
          end
        end
      end
    end
  end

  describe '#complete?' do
    context 'when inactive' do
      it 'returns false' do
        expect(startup_sequence.complete?).to be(false)
      end
    end

    context 'when active but not started' do
      before do
        startup_sequence.start
      end

      it 'returns false' do
        expect(startup_sequence.complete?).to be(false)
      end
    end

    context 'when position is within sequence' do
      before do
        startup_sequence.start
        Timecop.freeze(Time.now) do
          startup_sequence.advance
        end
      end

      it 'returns false' do
        expect(startup_sequence.complete?).to be(false)
      end
    end

    context 'when position reaches sequence size' do
      it 'stops automatically' do
        startup_sequence.start
        now = Time.now
        Timecop.freeze(now) do
          startup_sequence.advance
          expect(startup_sequence.active?).to be(true)

          Timecop.freeze(now + sequence.size + 1) do
            startup_sequence.advance
            expect(startup_sequence.active?).to be(false)
          end
        end
      end
    end
  end

  describe 'empty sequence' do
    let(:empty_sequence) { described_class.new([]) }

    it 'completes immediately on first advance' do
      empty_sequence.start
      Timecop.freeze(Time.now) do
        empty_sequence.advance
        expect(empty_sequence.active?).to be(false)
      end
    end
  end
end
