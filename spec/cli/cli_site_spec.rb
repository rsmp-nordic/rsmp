RSpec.describe 'CLI rsmp site', :type => :aruba do
  describe 'with no options' do
    it 'starts site' do
      run_cli 'rsmp site'
      expect_cli_output /Starting site/ 
    end
  end    

  describe 'with id option' do
    it 'starts site with id' do
      run_cli 'rsmp site -i RN+SI0639'
      expect_cli_output /Starting site RN\+SI0639/
    end
  end

  describe 'with supervisor option' do
    it 'uses ip and port' do
      run_cli 'rsmp site -s 127.0.0.8:12118'
      expect_cli_output /Connecting to supervisor at 127\.0\.0\.8:12118/
    end
  end

  describe 'with config file' do
    it 'uses uses id from config' do
      write_file 'spec/fixtures/site.yaml','site_id: RN+SI0932'
      run_cli 'rsmp site -c spec/fixtures/site.yaml'
      expect_cli_output /Starting site RN\+SI0932/
    end
  end

  describe 'with non-existing config file' do
    it 'prints error' do
      run_cli 'rsmp site -c bad/path/site.yaml'
      expect_cli_output 'Error: Config bad/path/site.yaml not found'
    end
  end
end