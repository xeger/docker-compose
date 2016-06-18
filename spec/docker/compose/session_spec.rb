describe Docker::Compose::Session do
  let(:shell) { double('shell', interactive: false) }
  subject(:session) { described_class.new(shell) }

  let(:exitstatus) { 0 }
  let(:status) { double('exit status', to_i: exitstatus) }
  let(:output) { '' }
  let(:command) { double('command',
                         status:status,
                         captured_output:output,
                         captured_error:'') }

  before do
    allow(status).to receive(:success?).and_return(exitstatus == 0)
    allow(shell).to receive(:run).and_return(command)
    allow(command).to receive(:join).and_return(command)
  end

  describe '.new' do
    it 'allows file override' do
      s1 = described_class.new(shell, file: 'foo.yml')
      expect(shell).to receive(:run).with('docker-compose', {file: 'foo.yml'}, anything, anything, anything)
      s1.up
    end
  end

  describe '#ps' do
    let(:hashes) { ['corned_beef', 'sweet_potato', 'afghan_black'] }
    let(:output) { hashes.join("\n") }

    before do
      hashes.each do |h|
        cmd = double('command',
                     status:status,
                     captured_output:"(#{h}) (xeger/#{h}:latest) (1 mb) (Up 1 second) (#{h}) () ()",
                     captured_error:'')
        allow(cmd).to receive(:join).and_return(cmd)
        expect(shell).to receive(:run).with('docker', 'ps', hash_including(f:"id=#{h}")).and_return(cmd)
        allow(shell).to receive(:interactive=)
      end
    end

    it 'lists containers' do
      session.ps
    end
  end

  describe '#up' do
    it 'runs containers' do
      expect(shell).to receive(:run).with('docker-compose', anything, 'up', anything, anything)
      expect(shell).to receive(:run).with('docker-compose', anything, 'up', hash_including(d:true), anything)
      session.up
      session.up detached:true
    end
  end

  describe '#rm' do
    it 'removes containers' do
      expect(shell).to receive(:run).with('docker-compose', anything, 'rm', hash_including(f:false,v:false), [])
      expect(shell).to receive(:run).with('docker-compose', anything, 'rm', hash_including(f:false,v:false), ['joebob'])
      expect(shell).to receive(:run).with('docker-compose', anything, 'rm', hash_including(f:true,v:true), [])
      session.rm
      session.rm 'joebob'
      session.rm force:true,volumes:true
    end
  end
end
