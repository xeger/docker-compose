describe Docker::Compose::Session do
  let(:shell) { double('shell') }
  subject(:session) { described_class.new(shell) }

  let(:exitstatus) { 0 }
  let(:output) { '' }

  before do
    allow(shell).to receive(:command).and_return([exitstatus, output])
  end

  describe '.new' do
    it 'allows file override' do
      s1 = described_class.new(shell, file: 'foo.yml')
      expect(shell).to receive(:command).with('docker-compose', {file: 'foo.yml'}, anything, anything, anything)
      s1.up
    end
  end

  describe '#up' do
    it 'runs containers' do
      expect(shell).to receive(:command).with('docker-compose', anything, 'up', anything, anything)
      expect(shell).to receive(:command).with('docker-compose', anything, 'up', hash_including(d:true), anything)
      session.up
      session.up detached:true
    end
  end
end
