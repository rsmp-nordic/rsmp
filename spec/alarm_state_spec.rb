require 'timecop'

RSpec.describe RSMP::AlarmState do
  let(:now) { Time.new(2022, 9, 30, 14, 55, 17).utc }
  let(:later) { Time.new(2022, 1, 23, 23, 17, 59).utc }
  let(:now_str) { RSMP::Clock.to_s(now) }
  let(:later_str) { RSMP::Clock.to_s(later) }
  let(:node) { RSMP::Node.new }
  let(:component_id) { 'C1' }
  let(:component) { RSMP::Component.new node: node, id: component_id }
  let(:code_id) { 'A0301' }
  let(:state) { RSMP::AlarmState.new component: component, code: code_id, timestamp: now }

  def create_state(**options)
    options[:timestamp] ||= now
    RSMP::AlarmState.new component: component, code: code_id, **options
  end

  describe '#initialize' do
    it 'sets defaults' do
      expect(state.component_id).to eq(component_id)
      expect(state.code).to eq(code_id)
      expect(state.suspended).to be(false)
      expect(state.acknowledged).to be(false)
      expect(state.active).to be(false)
      expect(state.timestamp).to eq(now)
      expect(state.category).to eq('D')
      expect(state.priority).to eq(2)
      expect(state.rvs).to eq([])
    end
  end

  describe '#self.create_from_message' do
    it 'sets attributes' do
      message = RSMP::AlarmIssue.new(
        'cId' => component_id,
        'aCId' => code_id,
        'aTs' => now_str,
        'ack' => 'notAcknowledged',
        'sS' => 'notSuspended',
        'aS' => 'inActive',
        'cat' => 'B',
        'pri' => '1',
        'rvs' => []
      )
      state = RSMP::AlarmState.create_from_message component, message
      expect(state.component_id).to eq(component_id)
      expect(state.code).to eq(code_id)
      expect(state.suspended).to be(false)
      expect(state.acknowledged).to be(false)
      expect(state.active).to be(false)
      expect(state.timestamp).to eq(now)
      expect(state.category).to eq('B')
      expect(state.priority).to eq(1)
      expect(state.rvs).to eq([])
    end
  end

  describe '#update_timestamp' do
    it 'updates timestamp' do
      Timecop.freeze(later) do
        state.update_timestamp
        expect(state.timestamp).to eq(later)
      end
    end
  end

  describe '#to_hash' do
    it 'returns a hash with rsmp message values' do
      state = create_state acknowledged: false, suspended: false, active: true,
                           category: 'B', priority: 1
      expect(state.to_hash).to eq({
                                    'cId' => component_id,
                                    'aCId' => code_id,
                                    'aTs' => now_str,
                                    'sS' => 'notSuspended',
                                    'ack' => 'notAcknowledged',
                                    'aS' => 'Active',
                                    'cat' => 'B',
                                    'pri' => '1',
                                    'rvs' => []
                                  })

      state = create_state acknowledged: true, suspended: true, active: false
      expect(state.to_hash).to eq({
                                    'cId' => component_id,
                                    'aCId' => code_id,
                                    'aTs' => now_str,
                                    'ack' => 'Acknowledged',
                                    'sS' => 'Suspended',
                                    'aS' => 'inActive',
                                    'cat' => 'D',
                                    'pri' => '2',
                                    'rvs' => []
                                  })
    end
  end

  describe '#acknowledge' do
    it 'sets acknowledged to true' do
      state = create_state acknowledged: false
      expect(state.acknowledged).to be(false)
      state.acknowledge
      expect(state.acknowledged).to be(true)
    end

    it 'returns true if changed' do
      state = create_state acknowledged: false
      expect(state.acknowledge).to be(true)
      state = create_state acknowledged: true
      expect(state.acknowledge).to be(false)
    end

    it 'updates timestamp' do
      state = create_state acknowledged: false
      expect(state.timestamp).to eq(now)
      Timecop.freeze(later) do
        state.acknowledge
        expect(state.timestamp).to eq(later)
      end
    end
  end

  describe '#suspend' do
    it 'sets suspended to true' do
      state = create_state suspended: false
      expect(state.suspended).to be(false)
      state.suspend
      expect(state.suspended).to be(true)
    end

    it 'returns true if changed' do
      state = create_state suspended: false
      expect(state.suspend).to be(true)
      state = create_state suspended: true
      expect(state.suspend).to be(false)
    end

    it 'updates timestamp' do
      state = create_state suspended: false
      expect(state.timestamp).to eq(now)
      Timecop.freeze(later) do
        state.suspend
        expect(state.timestamp).to eq(later)
      end
    end
  end

  describe '#resume' do
    it 'sets resumed to false' do
      state = create_state suspended: true
      expect(state.suspended).to be(true)
      state.resume
      expect(state.suspended).to be(false)
    end

    it 'returns true if changed' do
      state = create_state suspended: false
      expect(state.resume).to be(false)
      state = create_state suspended: true
      expect(state.resume).to be(true)
    end

    it 'updates timestamp' do
      state = create_state suspended: true
      expect(state.timestamp).to eq(now)
      Timecop.freeze(later) do
        state.resume
        expect(state.timestamp).to eq(later)
      end
    end
  end

  describe '#activate' do
    it 'sets active to true' do
      state = create_state active: false
      expect(state.active).to be(false)
      state.activate
      expect(state.active).to be(true)
    end

    it 'sets acknowledged to false' do
      state = create_state active: false, acknowledged: true
      expect(state.acknowledged).to be(true)
      state.activate
      expect(state.acknowledged).to be(false)
    end

    it 'updates timestamp' do
      state = create_state suspended: true
      expect(state.timestamp).to eq(now)
      Timecop.freeze(later) do
        state.activate
        expect(state.timestamp).to eq(later)
      end
    end
  end

  describe '#differ_from_message?' do
    it 'returns false if no attribute differes' do
      state = create_state
      message = RSMP::AlarmIssue.new(state.to_hash)
      expect(state.differ_from_message?(message)).to be(false)
    end

    it 'returns false if any attribute differes' do
      state = create_state
      message = RSMP::AlarmIssue.new(create_state(acknowledged: true))
      expect(state.differ_from_message?(message)).to be(true)

      message = RSMP::AlarmIssue.new(create_state(suspended: true))
      expect(state.differ_from_message?(message)).to be(true)

      message = RSMP::AlarmIssue.new(create_state(active: true))
      expect(state.differ_from_message?(message)).to be(true)

      message = RSMP::AlarmIssue.new(create_state(category: 'B'))
      expect(state.differ_from_message?(message)).to be(true)

      message = RSMP::AlarmIssue.new(create_state(priority: 1))
      expect(state.differ_from_message?(message)).to be(true)
    end
  end
end
