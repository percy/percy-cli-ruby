RSpec.describe Percy::Cli::Client do
  describe '#initialize' do
    let(:cli_client) { Percy::Cli::Client.new }

    it 'passes client info down to the lower level Percy client' do
      expect(cli_client.client.client_info).to eq("percy-cli/#{Percy::Cli::VERSION}")
    end
  end
end
