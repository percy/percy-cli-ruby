require 'digest'

RSpec.describe Percy::Cli::Snapshot do
  let(:root_dir) { File.expand_path('../testdata/', __FILE__) }

  describe '#run_snapshot' do
    xit 'snapshots a root directory of static files' do
      # TODO(fotinakis): tests for this.
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
  describe '#find_remote_urls' do
    it 'returns remote resources referenced throughout the static website' do
      root_paths = Percy::Cli.new.send(:find_root_paths, root_dir)
      resource_paths = Percy::Cli.new.send(:find_resource_paths, root_dir)

      remote_urls = Percy::Cli.new.send(:find_remote_urls, root_paths + resource_paths)
      expect(remote_urls).to match_array([
        # In index.html:
        'https://maxcdn.bootstrapcdn.com/bootstrap/3.3.4/css/bootstrap.min.css',
        'http://example.com:12345/test-no-protocol.css',
        'http://example.com:12345/test-duplicate.css',
        'http://example.com:12345/test-query-param.css?v=1',
        'http://example.com:12345/test-single-quotes.css',
        'http://example.com:12345/test-diff-tag-order.css',

        # In base.css:
        'http://ajax.googleapis.com/ajax/libs/jqueryui/1.11.4/themes/smoothness/jquery-ui.css',
      ])
    end
  end
  describe '#build_resources' do
    it 'returns resource objects' do
      paths = [File.join(root_dir, 'css/base.css')]
      resources = Percy::Cli.new.send(:build_resources, paths, root_dir)

      expect(resources.length).to eq(1)
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_nil
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
    it 'returns resource objects with is_root set if given' do
      paths = [File.join(root_dir, 'index.html')]
      resources = Percy::Cli.new.send(:build_resources, paths, root_dir, is_root: true)

      expect(resources.length).to eq(1)
      expect(resources.first.resource_url).to eq('/index.html')
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_truthy
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
    it 'encodes the resource_url' do
      paths = [File.join(root_dir, 'css/test with spaces.css')]
      resources = Percy::Cli.new.send(:build_resources, paths, root_dir)

      expect(resources.length).to eq(1)
      expect(resources.first.resource_url).to eq('/css/test%20with%20spaces.css')
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_nil
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
  end
  describe '#build_remote_resources' do
    it 'fetches the remote URLs and creates resource objects' do
      urls = [
        'https://maxcdn.bootstrapcdn.com/bootstrap/3.3.4/css/bootstrap.min.css',
        'http://example.com:12345/test-failure.css',
      ]
      stub_request(:get, 'http://example.com:12345/test-failure.css').to_return(status: 400)

      resources = Percy::Cli.new.send(:build_remote_resources, urls)

      expect(resources.length).to eq(1)
      expect(resources[0].resource_url).to eq(urls[0])
      expect(resources[0].sha).to be
      expect(resources[0].is_root).to be_nil
      expect(resources[0].content).to be
      expect(resources[0].path).to be_nil
    end
  end
  describe '#upload_snapshot' do
    xit 'uploads the given resources to the build' do
      # TODO(fotinakis): tests for this.
    end
  end
end
