RSpec.describe RSMP::TLC::Inputs do
  let(:inputs) { RSMP::TLC::Inputs.new 4 }

  it 'defaults to all inactive, released' do
    (1..4).each do |i|
      expect(inputs.value?(i)).to eq(false)
      expect(inputs.forced?(i)).to eq(false)
      expect(inputs.forced_value?(i)).to eq(false)
      expect(inputs.actual?(i)).to eq(false)
    end
  end

  it 'can get state strings' do
    expect(inputs.value_string).to eq('0000')
    expect(inputs.forced_string).to eq('0000')
    expect(inputs.forced_value_string).to eq('0000')
    expect(inputs.actual_string).to eq('0000')
  end

  it 'can report inputs' do
    (1..4).each do |i|
      expect(inputs.report(i)).to eq({ value: false, forced: false, forced_value: false, actual: false })
    end
  end

  it 'raises if input index is invalid' do
    expect { inputs.value?(0) }.to raise_error(ArgumentError)
    expect { inputs.set(0) }.to raise_error(ArgumentError)

    expect { inputs.force(0) }.to raise_error(ArgumentError)
    expect { inputs.forced?(0) }.to raise_error(ArgumentError)

    expect { inputs.value?(5) }.to raise_error(ArgumentError)
    expect { inputs.set(5) }.to raise_error(ArgumentError)
    expect { inputs.force(5) }.to raise_error(ArgumentError)
    expect { inputs.forced?(5) }.to raise_error(ArgumentError)
  end

  it 'can set value' do
    inputs.set(1, true)
    expect(inputs.value?(1)).to eq(true)
    expect(inputs.value_string).to eq('1000')
    inputs.set(1, false)
    expect(inputs.value?(1)).to eq(false)
    expect(inputs.value_string).to eq('0000')

    inputs.set(4, true)
    expect(inputs.value?(4)).to eq(true)
    expect(inputs.value_string).to eq('0001')
    inputs.set(4, false)
    expect(inputs.value?(4)).to eq(false)
    expect(inputs.value_string).to eq('0000')
  end

  it 'forces' do
    expect(inputs.value?(1)).to eq(false)
    inputs.force(1, true)
    expect(inputs.value?(1)).to eq(false)
  end

  it 'can force' do
    (1..4).each do |i|
      # when status is false
      inputs.set(i, false)
      expect(inputs.report(i)).to eq({ value: false, forced: false, forced_value: false, actual: false })

      inputs.force(i, true)
      expect(inputs.report(i)).to eq({ value: false, forced: true, forced_value: true, actual: true })

      inputs.force(i, false)
      expect(inputs.report(i)).to eq({ value: false, forced: true, forced_value: false, actual: false })

      inputs.release(i)
      expect(inputs.report(i)).to eq({ value: false, forced: false, forced_value: false, actual: false })

      # when status is true
      inputs.set(i, true)
      expect(inputs.report(i)).to eq({ value: true, forced: false, forced_value: false, actual: true })

      inputs.force(i, true)
      expect(inputs.report(i)).to eq({ value: true, forced: true, forced_value: true, actual: true })

      inputs.force(i, false)
      expect(inputs.report(i)).to eq({ value: true, forced: true, forced_value: false, actual: false })

      inputs.release(i)
      expect(inputs.report(i)).to eq({ value: true, forced: false, forced_value: false, actual: true })
    end
  end

  it 'reports change when setting value' do
    (1..4).each do |_i|
      expect(inputs.set(1, true)).to eq(true)
      expect(inputs.set(1, true)).to eq(nil)
      expect(inputs.set(1, false)).to eq(false)
      expect(inputs.set(1, false)).to eq(nil)
    end
  end

  it 'reports change when forcing' do
    (1..4).each do |_i|
      expect(inputs.force(1, true)).to eq(true)
      expect(inputs.force(1, true)).to eq(nil)
      expect(inputs.force(1, false)).to eq(false)
      expect(inputs.force(1, false)).to eq(nil)
    end
  end

  it 'reports change when releasing' do
    (1..4).each do |_i|
      expect(inputs.force(1)).to eq(true)
      expect(inputs.force(1)).to eq(nil)
      expect(inputs.release(1)).to eq(false)
      expect(inputs.release(1)).to eq(nil)
    end
  end

  it 'reports no change when setting value while forced' do
    (1..4).each do |_i|
      inputs.force(1)
      expect(inputs.set(1, true)).to eq(nil)
      expect(inputs.set(1, true)).to eq(nil)
      expect(inputs.set(1, false)).to eq(nil)
      expect(inputs.set(1, false)).to eq(nil)
    end
  end
end
