describe Docker::Compose::Session do
  let(:shell) { double(Docker::Compose::Shell) }
  subject(:session) { described_class.new(shell) }

  let(:exitstatus) { 0 }
  let(:output) { '' }

  before do
    allow(shell).to receive(:command).and_return([exitstatus, output])
  end

  describe '.new' do
    it 'allows file override' do
      s1 = described_class.new(shell, file: 'foo.yml')
      expect(shell).to receive(:command).with(array_including('--file=foo.yml'), anything)
      s1.up
    end
  end

  describe '#up' do
    it 'runs containers' do
      expect(shell).to receive(:command).with(array_including('up'), anything)
      expect(shell).to receive(:command).with(array_including('up'),hash_including(d:true))
      session.up
      session.up detached:true
    end
  end

  describe '#run!' do
    it 'emulates docker-compose 1.5 ${ENV} substitution' do
      expect(session).to receive(:run_without_substitution!)
      session.up
    end
  end
end
