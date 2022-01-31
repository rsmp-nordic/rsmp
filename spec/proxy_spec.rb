RSpec.describe RSMP::Proxy do
	let(:options) { {} }
	let(:proxy) { RSMP::Proxy.new options }

	describe '#wait_for_state' do
		it 'wakes up' do
			async_context(terminate:false) do |task|
				subtask = task.async do |subtask|
					proxy.wait_for_state :connected, timeout: 0.001
				end
				proxy.set_state :connected
				subtask.result
			end
		end

		it 'accepts array of states and returns current state' do
			async_context(terminate:false) do |task|
				subtask = task.async do |subtask|
					state = proxy.wait_for_state [:ok,:ready], timeout: 0.001
					expect(state).to eq(:ready)
				end
				proxy.set_state :ready
				subtask.result
			end
		end

		it 'times out' do
			async_context(terminate:false) do |task|
				expect {
					proxy.wait_for_state :connected, timeout: 0.001
				}.to raise_error(RSMP::TimeoutError)
			end
		end

		it 'returns immediately if state is already correct' do
			async_context(terminate:false) do |task|
				proxy.set_state :disconnected
				proxy.wait_for_state :disconnected, timeout: 0.001
			end
		end
	end

	describe '#wait_for_condition without block' do
		it 'wakes up' do
			async_context(terminate:false) do |task|
				condition = Async::Notification.new
				subtask = task.async do |subtask|
					proxy.wait_for_condition condition, timeout: 0.001
				end
				condition.signal
				subtask.result
			end
		end

		it 'times out' do
			async_context(terminate:false) do |task|
				condition = Async::Notification.new
				expect {
					proxy.wait_for_condition condition, timeout: 0.001
				}.to raise_error(RSMP::TimeoutError)
			end
		end
	end

	describe '#wait_for_condition with block' do
		it 'wakes up' do
			async_context(terminate:false) do |task|
				condition = Async::Notification.new
				result = nil
				subtask = task.async do |subtask|
					proxy.wait_for_condition condition, timeout: 1 do |state|
						result = (state == :banana)
						result
					end
				end
				condition.signal :pear
				task.yield
				expect(result).to be(false)

				condition.signal :apple
				task.yield
				expect(result).to be(false)

				condition.signal :banana
				task.yield
				expect(result).to be(true)

				subtask.result
			end
		end
	end
end
