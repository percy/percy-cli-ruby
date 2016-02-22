require 'digest'

RSpec.describe Percy::Cli::Snapshot do
  let(:root_dir) { File.expand_path('../testdata/', __FILE__) }

  describe '#run_snapshot' do
    xit 'snapshots a root directory of static files' do
      # TODO(fotinakis): tests for the full flow.
    end
  end
  describe '#rescue_connection_failures' do
    let(:cli) { Percy::Cli.new }
    it 'returns block result on success' do
      result = cli.send(:rescue_connection_failures) do
        true
      end
      expect(result).to eq(true)
      expect(cli.send(:failed?)).to eq(false)
    end
    it 'makes block safe from quota exceeded errors' do
      result = cli.send(:rescue_connection_failures) do
        raise Percy::Client::PaymentRequiredError.new(409, 'POST', '', '')
      end
      expect(result).to eq(nil)
      expect(cli.send(:failed?)).to eq(true)
    end
    it 'makes block safe from server errors' do
      result = cli.send(:rescue_connection_failures) do
        raise Percy::Client::ServerError.new(502, 'POST', '', '')
      end
      expect(result).to eq(nil)
      expect(cli.send(:failed?)).to eq(true)
    end
    it 'makes block safe from ConnectionFailed' do
      result = cli.send(:rescue_connection_failures) do
        raise Percy::Client::ConnectionFailed
      end
      expect(result).to eq(nil)
      expect(cli.send(:failed?)).to eq(true)
    end
    it 'makes block safe from TimeoutError' do
      result = cli.send(:rescue_connection_failures) do
        raise Percy::Client::TimeoutError
      end
      expect(result).to eq(nil)
      expect(cli.send(:failed?)).to eq(true)
    end
    it 'requires a block' do
      expect { cli.send(:rescue_connection_failures) }.to raise_error(ArgumentError)
    end
  end
  describe '#find_root_paths' do
    it 'returns only the HTML files in the directory' do
      paths = Percy::Cli.new.send(:find_root_paths, root_dir)
      expect(paths).to match_array([
        File.join(root_dir, 'index.html'),
        File.join(root_dir, 'subdir/test.html'),
      ])
    end
  end
  describe '#find_resource_paths' do
    it 'returns only the related static files in the directory' do
      paths = Percy::Cli.new.send(:find_resource_paths, root_dir)
      expect(paths).to match_array([
        File.join(root_dir, 'css/base.css'),
        File.join(root_dir, 'css/test with spaces.css'),
        File.join(root_dir, 'images/jellybeans.png'),
      ])
    end
  end
  describe '#build_resources' do
    it 'returns resource objects' do
      paths = [File.join(root_dir, 'css/base.css')]
      options = {baseurl: '/', strip_prefix: root_dir}
      resources = Percy::Cli.new.send(:build_resources, paths, options)

      expect(resources.length).to eq(1)
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_nil
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
    it 'returns resource objects with is_root set if given' do
      paths = [File.join(root_dir, 'index.html')]
      options = {baseurl: '/', strip_prefix: root_dir, is_root: true}
      resources = Percy::Cli.new.send(:build_resources, paths, options)

      expect(resources.length).to eq(1)
      expect(resources.first.resource_url).to eq('/index.html')
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_truthy
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
    it 'encodes the resource_url' do
      paths = [File.join(root_dir, 'css/test with spaces.css')]
      options = {baseurl: '/', strip_prefix: root_dir}
      resources = Percy::Cli.new.send(:build_resources, paths, options)

      expect(resources.length).to eq(1)
      expect(resources.first.resource_url).to eq('/css/test%20with%20spaces.css')
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_nil
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
    it 'prepends the baseurl if given' do
      paths = [File.join(root_dir, 'index.html')]
      options = {strip_prefix: root_dir, is_root: true, baseurl: '/test baseurl/'}
      resources = Percy::Cli.new.send(:build_resources, paths, options)

      expect(resources.length).to eq(1)
      expect(resources.first.resource_url).to eq('/test%20baseurl/index.html')
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_truthy
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
  end
  describe '#upload_snapshot' do
    xit 'uploads the given resources to the build' do
      # TODO(fotinakis): tests for this.
    end
  end
end
