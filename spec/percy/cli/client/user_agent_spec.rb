RSpec.describe Percy::Cli::Client::UserAgent do
  subject(:client) { Percy::Cli::Client.new }

  describe '#_environment_info' do
    subject(:environment_info) { client._environment_info }

    context 'an app with Middleman and Jekyll' do
      it 'returns full environment information' do
        expect(client).to receive(:_middleman_version).at_least(:once).times.and_return('4.2.1')
        expect(client).to receive(:_jekyll_version).at_least(:once).and_return('3.3.0')

        expect(environment_info).to eq('middleman/4.2.1; jekyll/3.3.0')
      end
    end

    context 'an app with no known frameworks being used' do
      it 'returns no environment information' do
        expect(environment_info).to be_empty
      end
    end
  end

  describe '#_client_info' do
    subject(:client_info) { client._client_info }

    it 'includes client information' do
      expect(client_info).to eq("percy-cli/#{Percy::Cli::VERSION}")
    end
  end
end
