RSpec.describe RSMP::CLI do
  describe 'invoke without arguments' do
    it 'prints help' do
      expect { RSMP::CLI.new.invoke("help") }
      .to output( a_string_including('Commands:') ).to_stdout
    end
  end

  describe 'invoke help' do
    it 'prints help' do
      expect { RSMP::CLI.new.invoke("help") }
      .to output( a_string_including('Commands:') ).to_stdout
    end
  end
  describe 'invoke site help' do
    it 'prints site help' do
      expect { RSMP::CLI.new.invoke("help", ['site']) }
      .to output( a_string_including('Usage:') ).to_stdout
    end
  end

end