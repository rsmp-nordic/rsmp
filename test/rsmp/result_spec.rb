require 'rsmp'

describe RSMP::Result do
  it 'wraps successful values' do
    result = subject.success(:value)

    expect(result.success?).to be == true
    expect(result.failure?).to be == false
    expect(result.value).to be == :value
    expect(result.value!).to be == :value
  end

  it 'wraps expected failures without raising' do
    result = subject.failure(
      :disconnected,
      message: 'The peer disconnected',
      source: :peer,
      context: { session_id: 7 }
    )

    expect(result.success?).to be == false
    expect(result.failure?).to be == true
    expect(result.value).to be_nil
    expect(result.failure.code).to be == :disconnected
    expect(result.failure.source).to be == :peer
    expect(result.failure.context).to be == { session_id: 7 }
  end

  it 'raises only when a failed result is explicitly unwrapped' do
    result = subject.failure(:timeout, message: 'Too slow', source: :timeout)

    expect { result.value! }.to raise_exception(
      RSMP::OperationError,
      message: be == 'Too slow'
    )
  end

  it 'maps successful values and preserves failures' do
    success = subject.success(2).map { |value| value * 3 }
    called = false
    failure = subject.failure(:timeout, source: :timeout).map { called = true }

    expect(success.value).to be == 6
    expect(failure.failure.code).to be == :timeout
    expect(called).to be == false
  end
end

describe RSMP::Completion do
  it 'stores completion for later waiters and resolves only once' do
    completion = subject.new
    completion.succeed(:first)
    completion.fail(:disconnected, source: :peer)

    expect(completion.wait.value).to be == :first
  end

  it 'returns a timeout without resolving the operation' do
    completion = subject.new
    result = completion.wait(timeout: 0.001)

    expect(result.failure.code).to be == :timeout
    expect(completion.resolved?).to be == false

    completion.succeed(:later)
    expect(completion.wait.value).to be == :later
  end

  it 'propagates unexpected exceptions unchanged' do
    completion = subject.new
    error = NoMethodError.new('internal defect')
    completion.crash(error)

    expect { completion.wait }.to raise_exception(NoMethodError, message: be == 'internal defect')
  end

  it 'does not confuse a rejected internal timeout with the caller wait timeout' do
    completion = subject.new
    completion.crash(Async::TimeoutError.new('internal timeout defect'))

    expect do
      completion.wait(timeout: 1)
    end.to raise_exception(Async::TimeoutError, message: be == 'internal timeout defect')
  end
end

describe RSMP::Validation do
  it 'represents valid and invalid validation outcomes' do
    valid = subject.new
    invalid = subject.new(violations: [['value', 'must be null']])

    expect(valid.valid?).to be == true
    expect(valid.invalid?).to be == false
    expect(invalid.valid?).to be == false
    expect(invalid.message).to be == 'value, must be null'
  end
end
