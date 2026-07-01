require 'sus'
require_relative '../../helper'

describe 'M0001' do
  let(:message) do
    {
      'mType' => 'rSMsg',
      'mId' => '4173c2c8-a933-43cb-9425-66d4613731ed',
      'type' => 'CommandRequest',
      'siteId' => [{ 'sId' => 'RN+SI0001' }],
      'cId' => 'O+14439=481WA001',
      'arg' => [
        {
          'cCI' => 'M0001',
          'n' => 'status',
          'cO' => 'setValue',
          'v' => 'YellowFlash'
        },
        {
          'cCI' => 'M0001',
          'n' => 'securityCode',
          'cO' => 'setValue',
          'v' => '1111'
        }
      ]
    }
  end

  it 'accepts valid command' do
    expect(validate(message)).to be_nil
  end

  it 'catches bad value' do
    message['arg'].first['v'] = 'bad'
    expect(validate(message)).to be == [['/arg/0/v', 'enum']]
  end

  it 'catches bad name' do
    message['arg'] << {
      'cCI' => 'M0001',
      'n' => 'bad',
      'cO' => 'setValue',
      'v' => 'YellowFlash'
    }
    expect(validate(message)).to be == [['/arg/2/n', 'enum']]
  end

  it 'catches bad status values' do
    message['arg'].first['n'] = 'status'
    message['arg'].first['v'] = 'bad'
    expect(validate(message)).to be == [['/arg/0/v', 'enum']]
  end

  it 'accepts timeout strings' do
    message['arg'] << {
      'cCI' => 'M0001',
      'n' => 'timeout',
      'cO' => 'setValue',
      'v' => '1440'
    }
    expect(validate(message)).to be_nil
  end

  it 'accepts intersection strings' do
    message['arg'] << {
      'cCI' => 'M0001',
      'n' => 'intersection',
      'cO' => 'setValue',
      'v' => '255'
    }
    expect(validate(message)).to be_nil
  end
end
