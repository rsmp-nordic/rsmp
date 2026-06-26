require 'rsmp'
require 'timecop'

def build(json)
  attributes = RSMP::Message.parse_attributes(json)
  message = RSMP::Message.build(attributes, json)
  unless message.is_a? RSMP::Unknown
    message.validate({
                       core: RSMP::Schema.latest_core_version,
                       tlc: RSMP::Schema.latest_version(:tlc)
                     })
  end
  message
end

def core_versions
  RSMP::Schema.core_versions.map { |version| { 'vers' => version } }
end

def sxl_version
  RSMP::Schema.latest_version(:tlc)
end

def sxls
  [{ 'name' => 'tlc', 'version' => sxl_version }]
end

describe RSMP::Message do
  let(:message_config) do
    {
      version_str: %({"mType":"rSMsg","type":"Version","step":"Request","RSMP":#{core_versions.to_json},"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","SXLS":#{sxls.to_json},"mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6"}),
      ack_str: '{"mType":"rSMsg","type":"MessageAck","oMId":"a54dc38b-7ddb-42a6-b6e8-95b0d00dad19"}',
      not_ack_str: '{"mType":"rSMsg","type":"MessageNotAck","rea":"since we are a rsmp::SupervisorProxy","oMId":"24b5e2d1-fd32-4f12-80cf-f32f8b2772af"}',
      watchdog_str: '{"mType":"rSMsg","type":"Watchdog","wTs":"2015-06-08T12:01:39.654Z","mId":"a8cafa58-31bc-40bb-b335-645b5ac985cd"}',
      command_request_str: '{"mType":"rSMsg","type":"CommandRequest","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","arg":[{"cCI":"M0001","n":"securityCode","cO":"setValue","v":"1111"},{"cCI":"M0001","n":"status","cO":"setValue","v":"NormalControl"}],"mId":"1a913af3-82ba-489b-8895-54c2fb56d728"}',
      command_response_str: '{"mType":"rSMsg","type":"CommandResponse","cId":"AA+BBCCC=DDDEE002","cTS":"2019-07-11T06:37:55.914Z","rvs":[{"cCI":"M0001","n":"status","v":"NormalControl","age":"recent"}],"mId":"f0f38584-e3ff-46f8-88a1-598e7de0e671"}',
      aggregated_status_str: ' {"mType":"rSMsg","type":"AggregatedStatus","aSTS":"2019-07-11T06:37:55.913Z","fP":null,"fS":null,"se":[false,false,false,false,false,false,false,false],"mId":"d9a904cc-b39d-4b72-ad67-f7d634552d36"}',
      status_request_str: '{"mType":"rSMsg","type":"StatusRequest","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","sS":[{"sCI":"S0001","n":"signalgroupstatus"}],"mId":"859e189e-c973-4b40-90c4-45a7a25f2dda"}',
      status_response_str: '{"mType":"rSMsg","type":"StatusResponse","cId":"AA+BBCCC=DDDEE002","sTs":"2019-07-11T06:37:56.096Z","sS":[{"sCI":"S0001","n":"signalgroupstatus","s":"90","q":"recent"}],"mId":"0872f9f4-caee-4495-96ef-68a5cf56c993"}',
      status_subscribe_str: '{"mType":"rSMsg","type":"StatusSubscribe","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","sS":[{"sCI":"S0001","n":"signalgroupstatus","uRt":"4","sOc":false}],"mId":"6aee9e40-c6cb-4cd8-8b7a-3ee8906043c9"}',
      status_unsubscribe_str: '{"mType":"rSMsg","type":"StatusUnsubscribe","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","sS":[{"sCI":"S0001","n":"signalgroupstatus"}],"mId":"bae361e1-7b26-48f3-9776-5aac815544da"}',
      status_update_str: '{"mType":"rSMsg","type":"StatusUpdate","cId":"AA+BBCCC=DDDEE002","sTs":"2019-07-11T06:37:56.103Z","sS":[{"sCI":"S0001","n":"signalgroupstatus","s":"98","q":"recent"}],"mId":"e0694101-4b8c-4832-9bd4-7ed598b247bd"}',
      alarm_suspended: '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Suspend","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.058Z","ack":"notAcknowledged","sS":"Suspended","aS":"inActive","cat":"D","pri":"2","rvs":[],"mId":"e2571baa-ce10-4f0b-aa7f-d50ae7881039"}',
      alarm_resumed: '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Suspend","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.070Z","ack":"notAcknowledged","sS":"notSuspended","aS":"inActive","cat":"D","pri":"2","rvs":[],"mId":"612abbb3-46a2-4cce-b227-068cd1d4862f"}',
      alarm_acknowledge: '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Acknowledge","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.070Z","mId":"612abbb3-46a2-4cce-b227-068cd1d4862f"}',
      alarm_acknowledged: '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Acknowledge","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.070Z","ack":"Acknowledged","sS":"notSuspended","aS":"Active","cat":"D","pri":"2","rvs":[],"mId":"612abbb3-46a2-4cce-b227-068cd1d4862f"}',
      unknown_str: '{"mType":"rSMsg","type":"SomeNonExistingMessage","mId":"c014bd2d-5671-4a19-b37e-50deef301b82"}',
      malformed_str: '{"mType":"rSMsg",mId":"c014bd2d-5671-4a19-b37e-50deef301b82"}'
    }
  end

  with 'when parsing json packages' do
    it 'raises ArgumentError when parsing nil' do
      expect { subject.parse_attributes(nil) }.to raise_exception(ArgumentError)
    end

    it 'raises InvalidPacket when parsing empty string' do
      expect { subject.parse_attributes('') }.to raise_exception(RSMP::InvalidPacket)
    end

    it 'raises InvalidPacket when parsing whitespace' do
      expect { subject.parse_attributes(' ') }.to raise_exception(RSMP::InvalidPacket)
      expect { subject.parse_attributes("\t") }.to raise_exception(RSMP::InvalidPacket)
      expect { subject.parse_attributes("\n") }.to raise_exception(RSMP::InvalidPacket)
      expect { subject.parse_attributes("\f") }.to raise_exception(RSMP::InvalidPacket)
      expect { subject.parse_attributes("\r") }.to raise_exception(RSMP::InvalidPacket)
    end

    it 'raises InvalidPacket when parsing invalid JSON' do
      expect { subject.parse_attributes('{"a":"1"') }.to raise_exception(RSMP::InvalidPacket)
      expect { subject.parse_attributes('"a":"1"}') }.to raise_exception(RSMP::InvalidPacket)
      expect { subject.parse_attributes('/') }.to raise_exception(RSMP::InvalidPacket)
    end

    it 'parses valid JSON' do
      expect(subject.parse_attributes('"string"')).to be == 'string'
      expect(subject.parse_attributes('123')).to be == 123
      expect(subject.parse_attributes('3.14')).to be_within(Float::EPSILON).of(3.14)
      expect(subject.parse_attributes('[1,2,3]')).to be == [1, 2, 3]
      expect(subject.parse_attributes('{"a":"1","b":"2"}')).to be == ({ 'a' => '1', 'b' => '2' })
    end
  end

  with 'when creating messages' do
    let(:json) do
      {
        'RSMP' => core_versions,
        'SXL' => sxl_version,
        'SXLS' => sxls,
        'mId' => '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6',
        'mType' => 'rSMsg',
        'siteId' => [{ 'sId' => 'RN+SI0001' }],
        'step' => 'Request',
        'type' => 'Version'
      }
    end

    it 'builds Version when parsing JSON' do
      expect(build(message_config[:version_str])).to be_a(RSMP::Version)
    end

    it 'builds MessageAck when parsing JSON' do
      expect(build(message_config[:ack_str])).to be_a(RSMP::MessageAck)
    end

    it 'builds MessageNotAck when parsing JSON' do
      expect(build(message_config[:not_ack_str])).to be_a(RSMP::MessageNotAck)
    end

    it 'builds Watchdog when parsing JSON' do
      expect(build(message_config[:watchdog_str])).to be_a(RSMP::Watchdog)
    end

    it 'builds CommandRequest when parsing JSON' do
      expect(build(message_config[:command_request_str])).to be_a(RSMP::CommandRequest)
    end

    it 'builds CommandResponse when parsing JSON' do
      expect(build(message_config[:command_response_str])).to be_a(RSMP::CommandResponse)
    end

    it 'builds AggregatedStatus when parsing JSON' do
      expect(build(message_config[:aggregated_status_str])).to be_a(RSMP::AggregatedStatus)
    end

    it 'builds StatusRequest when parsing JSON' do
      expect(build(message_config[:status_request_str])).to be_a(RSMP::StatusRequest)
    end

    it 'builds StatusResponse when parsing JSON' do
      expect(build(message_config[:status_response_str])).to be_a(RSMP::StatusResponse)
    end

    it 'builds StatusSubscribe when parsing JSON' do
      expect(build(message_config[:status_subscribe_str])).to be_a(RSMP::StatusSubscribe)
    end

    it 'builds StatusUnsubscribe when parsing JSON' do
      expect(build(message_config[:status_unsubscribe_str])).to be_a(RSMP::StatusUnsubscribe)
    end

    it 'builds AlarmSuspended when parsing JSON' do
      expect(build(message_config[:alarm_suspended])).to be_a(RSMP::AlarmSuspended)
    end

    it 'builds AlarmResumed when parsing JSON' do
      expect(build(message_config[:alarm_resumed])).to be_a(RSMP::AlarmResumed)
    end

    it 'builds AlarmAcknowledge when parsing JSON' do
      expect(build(message_config[:alarm_acknowledge])).to be_a(RSMP::AlarmAcknowledge)
    end

    it 'builds AlarmAcknowledged when parsing JSON' do
      expect(build(message_config[:alarm_acknowledged])).to be_a(RSMP::AlarmAcknowledged)
    end

    it 'builds StatusUpdate when parsing JSON' do
      expect(build(message_config[:status_update_str])).to be_a(RSMP::StatusUpdate)
    end

    it 'builds Unknown when parsing JSON' do
      expect(build(message_config[:unknown_str])).to be_a(RSMP::Unknown)
    end

    it 'does not create mId for MessageAck and MessageNotAck' do
      expect(build(message_config[:ack_str]).m_id).to be_nil
      expect(build(message_config[:not_ack_str]).m_id).to be_nil
    end

    it 'parses attributes values' do
      message = build(message_config[:version_str])
      expect(message.attributes).to be == json
    end

    it 'initializes attributes' do
      message = RSMP::Version.new json
      expect(message.attributes).to be == json
      expect(message.m_id).to be == json['mId']
    end

    it 'initializes timestamp' do
      time = Time.new(2019, 9, 1, 14, 24, 17)
      Timecop.freeze(time) do
        message = RSMP::Version.new json
        expect(message.timestamp).to be == time
      end
    end

    it 'randomizes message id if attributes are empty' do
      message = RSMP::Version.new
      expect(message.m_id).to be =~ /[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}/i
      another_message = RSMP::Version.new
      expect(message.m_id).not.to be == another_message.m_id
    end

    it 'builds specific message types' do
      expect(RSMP::Version.new.type).to be == 'Version'
      expect(RSMP::MessageAck.new.type).to be == 'MessageAck'
      expect(RSMP::MessageNotAck.new.type).to be == 'MessageNotAck'
      expect(RSMP::AggregatedStatus.new.type).to be == 'AggregatedStatus'
      expect(RSMP::Watchdog.new.type).to be == 'Watchdog'
      expect(RSMP::Alarm.new.type).to be == 'Alarm'
      expect(RSMP::CommandRequest.new.type).to be == 'CommandRequest'
      expect(RSMP::CommandResponse.new.type).to be == 'CommandResponse'
      expect(RSMP::StatusRequest.new.type).to be == 'StatusRequest'
      expect(RSMP::StatusResponse.new.type).to be == 'StatusResponse'
      expect(RSMP::StatusSubscribe.new.type).to be == 'StatusSubscribe'
      expect(RSMP::StatusUnsubscribe.new.type).to be == 'StatusUnsubscribe'
      expect(RSMP::StatusUpdate.new.type).to be == 'StatusUpdate'
      expect(RSMP::Unknown.new.type).to be_nil
      expect(RSMP::Malformed.new.type).to be_nil
      expect(subject.new.type).to be_nil
    end

    it 'generates json' do
      message = RSMP::Version.new(json)
      message.generate_json
      str = %({"mType":"rSMsg","type":"Version","RSMP":#{core_versions.to_json},"SXL":"#{sxl_version}","SXLS":#{sxls.to_json},"mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6","siteId":[{"sId":"RN+SI0001"}],"step":"Request"})
      expect(message.json).to be == str
    end

    it 'encodes status values using SXL argument types' do
      message = RSMP::StatusUpdate.new(
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [
          { 'sCI' => 'S0001', 'n' => 'basecyclecounter', 's' => 7, 'q' => 'recent' },
          { 'sCI' => 'S0001', 'n' => 'signalgroupstatus', 's' => '98', 'q' => 'recent' }
        ]
      )

      message.encode_for(core: '3.3.0', tlc: '1.3.0')

      expect(message.attributes['sS'].map { |item| item['s'] }).to be == ['7', '98']
    end

    it 'encodes legacy list values from scalar semantic values' do
      message = RSMP::StatusResponse.new(
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [
          { 'sCI' => 'S0007', 'n' => 'status', 's' => true, 'q' => 'recent' },
          { 'sCI' => 'S0007', 'n' => 'intersection', 's' => 0, 'q' => 'recent' }
        ]
      )

      message.encode_for(core: '3.3.0', tlc: '1.2.1')

      expect(message.attributes['sS'].map { |item| item['s'] }).to be == ['True', '0']
    end

    it 'encodes string values from scalar semantic values' do
      message = RSMP::StatusResponse.new(
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0004', 'n' => 'outputstatus', 's' => 0, 'q' => 'recent' }]
      )

      message.encode_for(core: '3.3.0', tlc: '1.2.1')

      expect(message.attributes['sS'].first['s']).to be == '0'
    end

    it 'encodes nested status values while preserving native arrays' do
      value = [{ 'intersection' => 1, 'startup' => true }]
      message = RSMP::StatusUpdate.new(
        'cId' => 'TLC001',
        'sTs' => '2024-01-01T10:00:00.000Z',
        'sS' => [{ 'sCI' => 'S0005', 'n' => 'statusByIntersection', 's' => value, 'q' => 'recent' }]
      )

      message.encode_for(core: '3.3.0', tlc: '1.3.0')

      expect(message.attributes['sS'].first['s']).to be == [{ 'intersection' => '1', 'startup' => 'True' }]
    end

    it 'encodes command values using SXL argument types' do
      message = RSMP::CommandRequest.new(
        'cId' => 'TLC001',
        'arg' => [
          { 'cCI' => 'M0019', 'n' => 'input', 'cO' => 'setValue', 'v' => 3 },
          { 'cCI' => 'M0019', 'n' => 'inputValue', 'cO' => 'setValue', 'v' => false }
        ]
      )

      message.encode_for(core: '3.3.0', tlc: '1.3.0')

      expect(message.attributes['arg'].map { |item| item['v'] }).to be == ['3', 'False']
    end

    it 'leaves native command values native' do
      message = RSMP::CommandRequest.new(
        'cId' => 'TLC001',
        'arg' => [{ 'cCI' => 'M0024', 'n' => 'status', 'cO' => 'setValue', 'v' => true }]
      )

      message.encode_for(core: '3.3.0', tlc: '1.3.0')

      expect(message.attributes['arg'].first['v']).to be == true
    end

    it 'encodes command response values using SXL argument types' do
      message = RSMP::CommandResponse.new(
        'cId' => 'TLC001',
        'cTS' => '2024-01-01T10:00:00.000Z',
        'rvs' => [{ 'cCI' => 'M0019', 'n' => 'inputValue', 'v' => true, 'age' => 'recent' }]
      )

      message.encode_for(core: '3.3.0', tlc: '1.3.0')

      expect(message.attributes['rvs'].first['v']).to be == 'True'
    end

    it 'encodes alarm rvs values using SXL argument types' do
      message = RSMP::AlarmIssue.new(
        'cId' => 'TLC001',
        'aCId' => 'A0302',
        'aTs' => '2024-01-01T10:00:00.000Z',
        'ack' => 'notAcknowledged',
        'sS' => 'notSuspended',
        'aS' => 'Active',
        'cat' => 'D',
        'pri' => '2',
        'rvs' => [{ 'n' => 'manual', 'v' => true }]
      )

      message.encode_for(core: '3.3.0', tlc: '1.3.0')

      expect(message.attributes['rvs'].first['v']).to be == 'True'
    end

    it 'validates mType' do
      message = subject.new 'mType' => 'rSMsg', 'type' => 'Version',
                            'mId' => 'c014bd2d-5671-4a19-b37e-50deef301b82'
      expect(message.validate_type?).to be == true

      message = subject.new 'mType' => 'rBad', 'type' => 'Version',
                            'mId' => 'c014bd2d-5671-4a19-b37e-50deef301b82'
      expect(message.validate_type?).to be == false
    end

    it 'validates message id format' do
      expect(subject.new('mType' => 'rSMsg', 'type' => 'Version',
                         'mId' => 'c014bd2d-5671-4a19-b37e-50deef301b82').validate_id?).to be == true
      expect(subject.new('mType' => 'rSMsg', 'type' => 'Version',
                         'mId' => '0c014bd2d-5671-4a19-b37e-50deef301b82').validate_id?).to be == true
      expect(subject.new('mType' => 'rSMsg', 'type' => 'Version',
                         'mId' => '.014bd2d-5671-4a19-b37e').validate_id?).to be == false
      expect(subject.new('mType' => 'rSMsg', 'type' => 'Version',
                         'mId' => '014bd2d-5671-4a19-b37e-50deef301b82').validate_id?).to be == false
      expect(subject.new('mType' => 'rSMsg', 'type' => 'Version',
                         'mId' => '14bd2d-5671-4a19-b37e-50deef301b82').validate_id?).to be == false
      expect(subject.new('mType' => 'rSMsg', 'type' => 'Version',
                         'mId' => 'c014bd2d5671-4a19-b37e-50deef301b82').validate_id?).to be == false
      expect(subject.new('mType' => 'rSMsg', 'type' => 'Version',
                         'mId' => 'c014bd2d5671-4a19-037e-50deef301b82').validate_id?).to be == false
    end
  end

  with 'when accessing attributes' do
    let(:message) { build(message_config[:version_str]) }

    it 'returns attribute values' do
      expect(message.attribute('SXL')).to be == sxl_version
    end

    it 'raises MissingAttribute when accessing non-existing attribute' do
      expect do
        message.attribute('bad')
      end.to raise_exception(RSMP::MissingAttribute, message: be == "missing attribute 'bad'")
    end

    it 'raises MissingAttribute when accessing attribute with wrong case' do
      expect do
        message.attribute('sxl')
      end.to raise_exception(RSMP::MissingAttribute,
                             message: be == "attribute 'SXL' should be named 'sxl'")
    end

    it 'returns type' do
      expect(message.type).to be == 'Version'
    end

    it 'returns message id' do
      expect(message.m_id).to be == '8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6'
    end
  end
end
