RSpec.describe(RSMP::CLI, :type => :aruba) do
  describe 'invoke site' do
    describe 'with no options' do
      it 'starts site' do
        AsyncRSpec.async do |task|
          expect_stdout( 'Starting site') do
            #raise 'ups'
            #1.upto(10) { |i| $stdout.puts i; sleep 1  }
            RSMP::CLI.new.invoke("site")
          end
        end
      end
    end

    describe 'with id option' do
      it 'starts site with id' do
        AsyncRSpec.async do |task|
          expect_stdout( 'Starting site RN+SI0639') do
            RSMP::CLI.new.invoke("site", [], id: 'RN+SI0639')
          end
        end
      end
    end

    describe 'with supervisor option' do
      it 'uses ip and port' do
        AsyncRSpec.async do |task|
          expect_stdout( 'Connecting to supervisor at 127.0.0.8:12118') do
            RSMP::CLI.new.invoke("site", [], supervisors: '127.0.0.8:12118')
          end
        end
      end
    end

    describe 'with config file' do
      it 'uses uses id from config' do
        write_file 'spec/fixtures/site.yaml', 'site_id: RN+SI0932'
        AsyncRSpec.async do |task|
          expect_stdout( 'Starting site RN+SI0932') do
            RSMP::CLI.new.invoke("site", [], config: 'tmp/aruba/spec/fixtures/site.yaml')
          end
        end
      end
    end

    describe 'with non-existing config file' do
      it 'prints error' do
        AsyncRSpec.async do |task|
          expect_stdout( 'Error: Config bad/path/site.yaml not found') do
            RSMP::CLI.new.invoke("site", [], config: 'bad/path/site.yaml')
          end
        end
      end
    end
  end
end