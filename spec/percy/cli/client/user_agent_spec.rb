RSpec.describe Percy::Cli::Client::UserAgent do
  subject(:client) { Percy::Cli::Client.new }

  describe '#_client_info' do
    subject(:client_info) { client._client_info }

    it 'includes client information' do
      expect(client_info).to eq("percy-cli/#{Percy::Cli::VERSION}")
    end
  end
end
