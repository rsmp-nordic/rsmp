RSpec.describe 'CLI rsmp help', :type => :aruba do
  describe 'with no options' do
    it 'prints help' do
      expect { RSMP::CLI.new.invoke("help") }
      .to output( a_string_including('Commands:') ).to_stdout
    end
  end

  describe 'with site' do
    it 'prints site help' do
      expect { RSMP::CLI.new.invoke("help", ['site']) }
      .to output( a_string_including('Usage:') ).to_stdout
    end
  end

end