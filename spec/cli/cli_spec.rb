RSpec.describe(RSMP::CLI) do
  describe "help" do
    it "lists commands" do
      expect { RSMP::CLI.new.invoke("help") }.to output(
        a_string_including('Commands:')
      ).to_stdout
    end
  end

  describe "version" do
    it "shows version" do
      expect { RSMP::CLI.new.invoke(:version) }.to output(
        a_string_including(RSMP::VERSION)
      ).to_stdout
    end
  end
end