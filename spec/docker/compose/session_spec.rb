describe Docker::Compose::Session do
  let(:shell) { double(Docker::Compose::Shell) }
  subject(:session) { described_class.new(shell) }

  let(:exitstatus) { 0 }
  let(:output) { '' }
  before do
    allow(shell).to receive(:run).and_return([exitstatus, output])
  end

  describe '.new' do
    it 'allows dir override' do
      s1 = described_class.new(shell, dir: 'bar')
      expect(shell).to receive(:run).with(array_including('--dir', 'bar'))
      s1.up
    end

    it 'allows file override' do
      s1 = described_class.new(shell, file: 'foo.yml')
      expect(shell).to receive(:run).with(array_including('--file', 'foo.yml'))
      s1.up
    end
  end

  describe '#up' do
    it 'runs containers' do
      expect(shell).to receive(:run).with(array_including('up'))
      expect(shell).to receive(:run).with(array_including('up', '--detached'))
      session.up
      session.up detached: true
      session.up detached: false
    end
  end

  describe '#run!' do
    it 'performs ${ENV} substitution'
  end
end
