Bundler.require(:default, :development)

def build json
	attributes = RSMP::Message.parse_attributes(json)
	message = RSMP::Message.build(attributes,json)
	message.validate({
		core: RSMP::Schema.latest_core_version,
		tlc: RSMP::Schema.latest_version(:tlc)
	}) unless message.is_a? RSMP::Unknown
	message
end

def core_versions
	RSMP::Schema.core_versions.map { |version| {"vers"=>version} }
end

def sxl_version
	RSMP::Schema.latest_version(:tlc)
end

RSpec.describe RSMP::Message do
	let(:version_str) { %({"mType":"rSMsg","type":"Version","RSMP":#{core_versions.to_json},"siteId":[{"sId":"RN+SI0001"}],"SXL":"#{sxl_version}","mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6","step":"Request"}) }
	let(:ack_str) { '{"mType":"rSMsg","type":"MessageAck","oMId":"a54dc38b-7ddb-42a6-b6e8-95b0d00dad19"}' }
	let(:not_ack_str) { '{"mType":"rSMsg","type":"MessageNotAck","rea":"since we are a rsmp::SupervisorProxy","oMId":"24b5e2d1-fd32-4f12-80cf-f32f8b2772af"}' }
	let(:watchdog_str) { '{"mType":"rSMsg","type":"Watchdog","wTs":"2015-06-08T12:01:39.654Z","mId":"a8cafa58-31bc-40bb-b335-645b5ac985cd"}' }
	let(:command_request_str) { '{"mType":"rSMsg","type":"CommandRequest","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","arg":[{"cCI":"M0001","n":"status","cO":"setValue","v":"NormalControl"}],"mId":"1a913af3-82ba-489b-8895-54c2fb56d728"}' }
	let(:command_response_str) { '{"mType":"rSMsg","type":"CommandResponse","cId":"AA+BBCCC=DDDEE002","cTS":"2019-07-11T06:37:55.914Z","rvs":[{"cCI":"M0001","n":"status","v":"NormalControl","age":"recent"}],"mId":"f0f38584-e3ff-46f8-88a1-598e7de0e671"}' }
	let(:aggregated_status_str) { ' {"mType":"rSMsg","type":"AggregatedStatus","aSTS":"2019-07-11T06:37:55.913Z","fP":null,"fS":null,"se":[false,false,false,false,false,false,false,false],"mId":"d9a904cc-b39d-4b72-ad67-f7d634552d36"}' }
	let(:status_request_str) { '{"mType":"rSMsg","type":"StatusRequest","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","sS":[{"sCI":"S0001","n":"signalgroupstatus"}],"mId":"859e189e-c973-4b40-90c4-45a7a25f2dda"}' }
	let(:status_response_str) { '{"mType":"rSMsg","type":"StatusResponse","cId":"AA+BBCCC=DDDEE002","sTs":"2019-07-11T06:37:56.096Z","sS":[{"sCI":"S0001","n":"signalgroupstatus","s":"90","q":"recent"}],"mId":"0872f9f4-caee-4495-96ef-68a5cf56c993"}' }
	let(:status_subscribe_str) { '{"mType":"rSMsg","type":"StatusSubscribe","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","sS":[{"sCI":"S0001","n":"signalgroupstatus","uRt":"4","sOc":false}],"mId":"6aee9e40-c6cb-4cd8-8b7a-3ee8906043c9"}' }
	let(:status_unsubscribe_str) { '{"mType":"rSMsg","type":"StatusUnsubscribe","ntsOId":"","xNId":"","cId":"AA+BBCCC=DDDEE002","sS":[{"sCI":"S0001","n":"signalgroupstatus"}],"mId":"bae361e1-7b26-48f3-9776-5aac815544da"}' }
	let(:status_update_str) { '{"mType":"rSMsg","type":"StatusUpdate","cId":"AA+BBCCC=DDDEE002","sTs":"2019-07-11T06:37:56.103Z","sS":[{"sCI":"S0001","n":"signalgroupstatus","s":"98","q":"recent"}],"mId":"e0694101-4b8c-4832-9bd4-7ed598b247bd"}' }
	let(:alarm_suspended) { '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Suspend","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.058Z","ack":"notAcknowledged","sS":"Suspended","aS":"inActive","cat":"D","pri":"2","rvs":[],"mId":"e2571baa-ce10-4f0b-aa7f-d50ae7881039"}' }
	let(:alarm_resumed) { '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Suspend","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.070Z","ack":"notAcknowledged","sS":"notSuspended","aS":"inActive","cat":"D","pri":"2","rvs":[],"mId":"612abbb3-46a2-4cce-b227-068cd1d4862f"}' }
	let(:alarm_acknowledge) { '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Acknowledge","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.070Z","mId":"612abbb3-46a2-4cce-b227-068cd1d4862f"}' }
	let(:alarm_acknowledged) { '{"mType":"rSMsg","type":"Alarm","ntsOId":"","xNId":"","xACId":"","xNACId":"","aSp":"Acknowledge","cId":"TC","aCId":"A0301","aTs":"2022-08-24T13:35:07.070Z","ack":"Acknowledged","sS":"notSuspended","aS":"Active","cat":"D","pri":"2","rvs":[],"mId":"612abbb3-46a2-4cce-b227-068cd1d4862f"}' }
	let(:unknown_str) { '{"mType":"rSMsg","type":"SomeNonExistingMessage","mId":"c014bd2d-5671-4a19-b37e-50deef301b82"}' }
	let(:malformed_str) { '{"mType":"rSMsg",mId":"c014bd2d-5671-4a19-b37e-50deef301b82"}' }

	context 'when parsing json packages' do
		it 'raises ArgumentError when parsing nil' do
			expect { RSMP::Message.parse_attributes(nil) }.to raise_error(ArgumentError)
		end

		it 'raises InvalidPacket when parsing empty string' do
			expect { RSMP::Message.parse_attributes('') }.to raise_error(RSMP::InvalidPacket)
		end

		it 'raises InvalidPacket when parsing whitespace' do
			expect { RSMP::Message.parse_attributes(' ') }.to raise_error(RSMP::InvalidPacket)
			expect { RSMP::Message.parse_attributes("\t") }.to raise_error(RSMP::InvalidPacket)
			expect { RSMP::Message.parse_attributes("\n") }.to raise_error(RSMP::InvalidPacket)
			expect { RSMP::Message.parse_attributes("\f") }.to raise_error(RSMP::InvalidPacket)
			expect { RSMP::Message.parse_attributes("\r") }.to raise_error(RSMP::InvalidPacket)
		end

		it 'raises InvalidPacket when parsing invalid JSON ' do
			expect { RSMP::Message.parse_attributes('{"a":"1"') }.to raise_error(RSMP::InvalidPacket)
			expect { RSMP::Message.parse_attributes('"a":"1"}') }.to raise_error(RSMP::InvalidPacket)
			expect { RSMP::Message.parse_attributes('/') }.to raise_error(RSMP::InvalidPacket)
		end

		it 'parses valid JSON' do
			expect(RSMP::Message.parse_attributes('"string"')).to eq("string")
			expect(RSMP::Message.parse_attributes('123')).to eq(123)
			expect(RSMP::Message.parse_attributes('3.14')).to eq(3.14)
			expect(RSMP::Message.parse_attributes('[1,2,3]')).to eq([1,2,3])
			expect(RSMP::Message.parse_attributes('{"a":"1","b":"2"}')).to eq({"a"=>"1","b"=>"2"})
		end
	end

	context 'when creating messages' do
		let(:json) {{
			 "RSMP" => core_versions,
       "SXL" => sxl_version,
       "mId" => "8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6",
       "mType" => "rSMsg",
       "siteId" => [{"sId"=>"RN+SI0001"}],
       "type" => "Version",
			 "step" => "Request"
		}}

		it 'builds right type of objects when parsing JSON' do
			expect(build(version_str)).to be_instance_of(RSMP::Version)
			expect(build(ack_str)).to be_instance_of(RSMP::MessageAck)
			expect(build(not_ack_str)).to be_instance_of(RSMP::MessageNotAck)
			expect(build(watchdog_str)).to be_instance_of(RSMP::Watchdog)
			expect(build(command_request_str)).to be_instance_of(RSMP::CommandRequest)
			expect(build(command_response_str)).to be_instance_of(RSMP::CommandResponse)
			expect(build(aggregated_status_str)).to be_instance_of(RSMP::AggregatedStatus)
			expect(build(status_request_str)).to be_instance_of(RSMP::StatusRequest)
			expect(build(status_response_str)).to be_instance_of(RSMP::StatusResponse)
			expect(build(status_subscribe_str)).to be_instance_of(RSMP::StatusSubscribe)
			expect(build(status_unsubscribe_str)).to be_instance_of(RSMP::StatusUnsubscribe)
			expect(build(alarm_suspended)).to be_instance_of(RSMP::AlarmSuspended)
			expect(build(alarm_resumed)).to be_instance_of(RSMP::AlarmResumed)
			expect(build(alarm_acknowledge)).to be_instance_of(RSMP::AlarmAcknowledge)
			expect(build(alarm_acknowledged)).to be_instance_of(RSMP::AlarmAcknowledged)
			expect(build(status_update_str)).to be_instance_of(RSMP::StatusUpdate)
			expect(build(unknown_str)).to be_instance_of(RSMP::Unknown)
		end

		it 'should not creat mId for MessageAck and MessageNotAck' do
			expect(build(ack_str).m_id).to be_nil
			expect(build(not_ack_str).m_id).to be_nil
		end

		it 'parses attributes values' do
			message = build(version_str)
			expect(message.attributes).to eq(json)
		end

		it 'initializes attributes' do
			message = RSMP::Version.new json
			expect(message.attributes).to eq(json)
			expect(message.m_id).to eq(json["mId"])
		end

		it 'initializes timestamp' do
			time = Time.new(2019, 9, 1, 14, 24, 17)
			Timecop.freeze(time) do
				message = RSMP::Version.new json
				expect(message.timestamp).to eq(time)
			end
		end

		it 'randomizes message id if attributes are empty' do
			message = RSMP::Version.new
			expect(message.m_id).to match(/[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}/i)
			another_message = RSMP::Version.new
			expect(message.m_id).not_to eq(another_message.m_id)
		end

		it 'builds specific message types' do
			expect(RSMP::Version.new.type).to eq("Version")
			expect(RSMP::MessageAck.new.type).to eq("MessageAck")
			expect(RSMP::MessageNotAck.new.type).to eq("MessageNotAck")
			expect(RSMP::AggregatedStatus.new.type).to eq("AggregatedStatus")
			expect(RSMP::Watchdog.new.type).to eq("Watchdog")
			expect(RSMP::Alarm.new.type).to eq("Alarm")
			expect(RSMP::CommandRequest.new.type).to eq("CommandRequest")
			expect(RSMP::CommandResponse.new.type).to eq("CommandResponse")
			expect(RSMP::StatusRequest.new.type).to eq("StatusRequest")
			expect(RSMP::StatusResponse.new.type).to eq("StatusResponse")
			expect(RSMP::StatusSubscribe.new.type).to eq("StatusSubscribe")
			expect(RSMP::StatusUnsubscribe.new.type).to eq("StatusUnsubscribe")
			expect(RSMP::StatusUpdate.new.type).to eq("StatusUpdate")
			expect(RSMP::Unknown.new.type).to be_nil
			expect(RSMP::Malformed.new.type).to be_nil
			expect(RSMP::Unknown.new.type).to be_nil
			expect(RSMP::Message.new.type).to be_nil
		end

		it 'generates json' do
			message = RSMP::Version.new(json)
			message.generate_json
			str = %({"mType":"rSMsg","type":"Version","RSMP":#{core_versions.to_json},"SXL":"#{sxl_version}","mId":"8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6","siteId":[{"sId":"RN+SI0001"}],"step":"Request"})
			expect(message.json).to eq(str)
		end

		it 'validates mType' do
			message = RSMP::Message.new "mType"=>"rSMsg","type"=>"Version","mId"=>"c014bd2d-5671-4a19-b37e-50deef301b82"
			expect(message.validate_type).to eq(true)

			message = RSMP::Message.new "mType"=>"rBad","type"=>"Version","mId"=>"c014bd2d-5671-4a19-b37e-50deef301b82"
			expect(message.validate_type).to eq(false)
		end

		it 'validates message id format' do
			expect(RSMP::Message.new("mType"=>"rSMsg","type"=>"Version","mId"=>"c014bd2d-5671-4a19-b37e-50deef301b82").validate_id).to eq(true)
			expect(RSMP::Message.new("mType"=>"rSMsg","type"=>"Version","mId"=>"0c014bd2d-5671-4a19-b37e-50deef301b82").validate_id).to eq(true)
			expect(RSMP::Message.new("mType"=>"rSMsg","type"=>"Version","mId"=>".014bd2d-5671-4a19-b37e").validate_id).to eq(false)
			expect(RSMP::Message.new("mType"=>"rSMsg","type"=>"Version","mId"=>"014bd2d-5671-4a19-b37e-50deef301b82").validate_id).to eq(false)
			expect(RSMP::Message.new("mType"=>"rSMsg","type"=>"Version","mId"=>"14bd2d-5671-4a19-b37e-50deef301b82").validate_id).to eq(false)
			expect(RSMP::Message.new("mType"=>"rSMsg","type"=>"Version","mId"=>"c014bd2d5671-4a19-b37e-50deef301b82").validate_id).to eq(false)
			expect(RSMP::Message.new("mType"=>"rSMsg","type"=>"Version","mId"=>"c014bd2d5671-4a19-037e-50deef301b82").validate_id).to eq(false)
		end
	end

	context 'when accessing attributes' do
		let(:message) { build(version_str) }

		it 'returns attribute values' do
			expect( message.attribute("SXL") ).to eq(sxl_version)
		end

		it 'raises MissingAttribute when accessing non-existing attribute' do
			expect { message.attribute("bad") }.to raise_error(RSMP::MissingAttribute, "missing attribute 'bad'")
		end

		it 'raises MissingAttribute when accessing attribute with wrong case' do
			expect { message.attribute("sxl") }.to raise_error(RSMP::MissingAttribute, "attribute 'SXL' should be named 'sxl'")
		end

		it 'returns type' do
			expect(message.type).to eq('Version')
		end

		it 'returns message id' do
			expect(message.m_id).to eq('8db00f0a-4124-406f-b3f9-ceb0dbe4aeb6')
		end
	end

end
