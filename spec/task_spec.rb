RSpec.describe RSMP::Task do
	class TaskTest
		include RSMP::Task
		def run
			loop do
				@task.sleep 1
			end
		end
	end

	let(:obj) { TaskTest.new }

	describe 'initialize' do
		it 'does not create task' do
			expect(obj.task).to be_nil
		end
	end

	describe 'start' do
		it 'creates task' do
			async_context do |task|
				obj.start
				expect(obj.task).to be_a(Async::Task)
				expect(obj.task.status).to eq(:running)
			end
		end

		it 'calls run' do
			async_context do |task|
				expect(obj).to receive(:run)
				obj.start
			end
		end

	end

	describe 'start' do
		it 'can be called several times' do
			async_context do |task|
				obj.start
				obj.start
				expect(obj.task).to be_a(Async::Task)
				expect(obj.task.status).to eq(:running)
			end
		end
	end

	describe 'stop' do
		it 'stops the task' do
			async_context do |task|
				obj.start
				obj.stop
				expect(obj.task).to be_nil
				expect(obj.status).to be_nil
			end
		end
	end

	describe 'restart' do
		it 'raises Restart' do
			async_context do |task|
				obj.start
				expect(obj.task).to be_a(Async::Task)
				expect(obj.task.status).to eq(:running)
				
				first_task = obj.task
				expect { obj.restart }.to raise_error(RSMP::Restart)
			end
		end
	end
end