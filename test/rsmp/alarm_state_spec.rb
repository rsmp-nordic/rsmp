require 'timecop'

describe RSMP::AlarmState do
  let(:times) do
    now = Time.new(2022, 9, 30, 14, 55, 17).utc
    later = Time.new(2022, 1, 23, 23, 17, 59).utc
    {
      now: now,
      later: later,
      now_str: RSMP::Clock.to_s(now),
      later_str: RSMP::Clock.to_s(later)
    }
  end

  let(:node) { RSMP::Node.new }
  let(:component) { RSMP::Component.new node: node, id: 'C1' }
  let(:state) { subject.new component: component, code: 'A0301', timestamp: times[:now] }

  def create_state(**options)
    options[:timestamp] ||= times[:now]
    RSMP::AlarmState.new component: component, code: 'A0301', **options
  end

  def alarm_message(ack:, suspended:, active:)
    RSMP::AlarmIssue.new(
      'cId' => 'C1',
      'aCId' => 'A0301',
      'aTs' => times[:now_str],
      'ack' => ack,
      'sS' => suspended,
      'aS' => active,
      'cat' => 'D',
      'pri' => '2',
      'rvs' => []
    )
  end

  [
    ['notAcknowledged', 'notSuspended', 'inActive', [false, false, false]],
    ['Acknowledged', 'Suspended', 'Active', [true, true, true]],
    ['Acknowledged', 'notSuspended', 'inActive', [true, false, false]],
    ['notAcknowledged', 'Suspended', 'inActive', [false, true, false]],
    ['notAcknowledged', 'notSuspended', 'Active', [false, false, true]]
  ].each do |ack, suspended, active, expected|
    %i[itself downcase].each do |casing|
      with "incoming #{ack}, #{suspended}, #{active} (#{casing})" do
        let(:message) do
          alarm_message(
            ack: ack.public_send(casing),
            suspended: suspended.public_send(casing),
            active: active.public_send(casing)
          )
        end

        it 'creates the reported state from a message' do
          alarm = subject.create_from_message(component, message)

          expect([alarm.acknowledged, alarm.suspended, alarm.active]).to be == expected
        end

        it 'updates each flag from its opposite state' do
          alarm = create_state(
            acknowledged: !expected[0], suspended: !expected[1], active: !expected[2],
            timestamp: times[:now] - 1
          )

          alarm.update_from_message(message)

          expect([alarm.acknowledged, alarm.suspended, alarm.active]).to be == expected
          expect(alarm.timestamp).to be == times[:now]
          expect(alarm.differ_from_message?(message)).to be == false
        end
      end
    end
  end

  with 'incoming component alarms' do
    let(:component) { RSMP::ComponentProxy.new node: node, id: 'C1' }

    it 'stores an active, acknowledged and suspended alarm' do
      component.handle_alarm(alarm_message(ack: 'Acknowledged', suspended: 'Suspended', active: 'Active'))

      alarm = component.alarms.fetch('A0301')
      expect(alarm.active).to be == true
      expect(alarm.acknowledged).to be == true
      expect(alarm.suspended).to be == true
    end
  end

  with '#initialize' do
    it 'sets defaults' do
      expect(state.component_id).to be == 'C1'
      expect(state.code).to be == 'A0301'
      expect(state.suspended).to be == false
      expect(state.acknowledged).to be == false
      expect(state.active).to be == false
      expect(state.timestamp).to be == times[:now]
      expect(state.category).to be == 'D'
      expect(state.priority).to be == 2
      expect(state.rvs).to be == []
    end
  end

  with '#self.create_from_message' do
    it 'sets attributes' do
      message = RSMP::AlarmIssue.new(
        'cId' => 'C1',
        'aCId' => 'A0301',
        'aTs' => times[:now_str],
        'ack' => 'notAcknowledged',
        'sS' => 'notSuspended',
        'aS' => 'inActive',
        'cat' => 'B',
        'pri' => '1',
        'rvs' => []
      )
      s = subject.create_from_message component, message
      expect(s.component_id).to be == 'C1'
      expect(s.code).to be == 'A0301'
      expect(s.suspended).to be == false
      expect(s.acknowledged).to be == false
      expect(s.active).to be == false
      expect(s.timestamp).to be == times[:now]
      expect(s.category).to be == 'B'
      expect(s.priority).to be == 1
      expect(s.rvs).to be == []
    end
  end

  with '#update_timestamp' do
    it 'updates timestamp' do
      Timecop.freeze(times[:later]) do
        state.update_timestamp
        expect(state.timestamp).to be == times[:later]
      end
    end
  end

  with '#to_hash' do
    it 'returns a hash with rsmp message values' do
      s = create_state acknowledged: false, suspended: false, active: true,
                       category: 'B', priority: 1
      expect(s.to_hash).to be == {
        'cId' => 'C1',
        'aCId' => 'A0301',
        'aTs' => times[:now_str],
        'sS' => 'notSuspended',
        'ack' => 'notAcknowledged',
        'aS' => 'Active',
        'cat' => 'B',
        'pri' => '1',
        'rvs' => []
      }

      s = create_state acknowledged: true, suspended: true, active: false
      expect(s.to_hash).to be == {
        'cId' => 'C1',
        'aCId' => 'A0301',
        'aTs' => times[:now_str],
        'ack' => 'Acknowledged',
        'sS' => 'Suspended',
        'aS' => 'inActive',
        'cat' => 'D',
        'pri' => '2',
        'rvs' => []
      }
    end
  end

  with '#acknowledge' do
    it 'sets acknowledged to true' do
      s = create_state acknowledged: false
      expect(s.acknowledged).to be == false
      s.acknowledge
      expect(s.acknowledged).to be == true
    end

    it 'returns true if changed' do
      s = create_state acknowledged: false
      expect(s.acknowledge).to be == true
      s = create_state acknowledged: true
      expect(s.acknowledge).to be == false
    end

    it 'updates timestamp' do
      s = create_state acknowledged: false
      expect(s.timestamp).to be == times[:now]
      Timecop.freeze(times[:later]) do
        s.acknowledge
        expect(s.timestamp).to be == times[:later]
      end
    end
  end

  with '#suspend' do
    it 'sets suspended to true' do
      s = create_state suspended: false
      expect(s.suspended).to be == false
      s.suspend
      expect(s.suspended).to be == true
    end

    it 'returns true if changed' do
      s = create_state suspended: false
      expect(s.suspend).to be == true
      s = create_state suspended: true
      expect(s.suspend).to be == false
    end

    it 'updates timestamp' do
      s = create_state suspended: false
      expect(s.timestamp).to be == times[:now]
      Timecop.freeze(times[:later]) do
        s.suspend
        expect(s.timestamp).to be == times[:later]
      end
    end
  end

  with '#resume' do
    it 'sets resumed to false' do
      s = create_state suspended: true
      expect(s.suspended).to be == true
      s.resume
      expect(s.suspended).to be == false
    end

    it 'returns true if changed' do
      s = create_state suspended: false
      expect(s.resume).to be == false
      s = create_state suspended: true
      expect(s.resume).to be == true
    end

    it 'updates timestamp' do
      s = create_state suspended: true
      expect(s.timestamp).to be == times[:now]
      Timecop.freeze(times[:later]) do
        s.resume
        expect(s.timestamp).to be == times[:later]
      end
    end
  end

  with '#activate' do
    it 'sets active to true' do
      s = create_state active: false
      expect(s.active).to be == false
      s.activate
      expect(s.active).to be == true
    end

    it 'sets acknowledged to false' do
      s = create_state active: false, acknowledged: true
      expect(s.acknowledged).to be == true
      s.activate
      expect(s.acknowledged).to be == false
    end

    it 'updates timestamp' do
      s = create_state suspended: true
      expect(s.timestamp).to be == times[:now]
      Timecop.freeze(times[:later]) do
        s.activate
        expect(s.timestamp).to be == times[:later]
      end
    end
  end

  with '#differ_from_message?' do
    it 'returns false if no attribute differs' do
      s = create_state
      message = RSMP::AlarmIssue.new(s.to_hash)
      expect(s.differ_from_message?(message)).to be == false
    end

    it 'returns true if any attribute differs' do
      s = create_state
      message = RSMP::AlarmIssue.new(create_state(acknowledged: true))
      expect(s.differ_from_message?(message)).to be == true

      message = RSMP::AlarmIssue.new(create_state(suspended: true))
      expect(s.differ_from_message?(message)).to be == true

      message = RSMP::AlarmIssue.new(create_state(active: true))
      expect(s.differ_from_message?(message)).to be == true

      message = RSMP::AlarmIssue.new(create_state(category: 'B'))
      expect(s.differ_from_message?(message)).to be == true

      message = RSMP::AlarmIssue.new(create_state(priority: 1))
      expect(s.differ_from_message?(message)).to be == true
    end
  end
end
