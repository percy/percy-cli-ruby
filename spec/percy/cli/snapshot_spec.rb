require 'digest'

RSpec.describe Percy::Cli::Snapshot do
  let(:root_dir) { File.expand_path('../testdata/', __FILE__) }

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
      ])
    end
  end
  describe '#build_resources' do
    it 'returns resource objects' do
      strip_prefix = root_dir
      paths = [File.join(root_dir, 'css/base.css')]
      resources = Percy::Cli.new.send(:build_resources, paths, strip_prefix)

      expect(resources.length).to eq(1)
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_nil
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
    it 'returns resource objects with is_root set if given' do
      strip_prefix = root_dir
      paths = [File.join(root_dir, 'index.html')]
      resources = Percy::Cli.new.send(:build_resources, paths, strip_prefix, is_root: true)

      expect(resources.length).to eq(1)
      expect(resources.first.sha).to eq(Digest::SHA256.hexdigest(File.read(paths.first)))
      expect(resources.first.is_root).to be_truthy
      expect(resources.first.content).to be_nil
      expect(resources.first.path).to eq(paths.first)
    end
  end
  describe '#upload_snapshot' do
    xit 'uploads the given resources to the build' do
    end
  end
end
