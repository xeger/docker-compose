describe Docker::Compose::Session do
  let(:shell) { double('shell', :interactive => false, :"interactive=" => true, :"chdir=" => true) }
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

  describe '#build' do
    it 'creates images' do
      expect(shell).to receive(:run).with('docker-compose', 'build', ['alice', 'bob'], {}).once
      session.build('alice', 'bob')
      expect(shell).to receive(:run).with('docker-compose', 'build', [], {force_rm:true, no_cache:true, pull:true}).once
      session.build(force_rm:true, no_cache:true, pull:true)
    end
  end

  describe '#ps' do
    let(:hashes) { ['corned_beef', 'sweet_potato', 'afghan_black'] }
    let(:output) { hashes.join("\n") }

    # Mock some additional calls to run! that the ps method makes in order
    # to get info about each container
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
      expect(shell).to receive(:run).with('docker-compose', 'up', {}, [])
      expect(shell).to receive(:run).with('docker-compose', 'up', hash_including(d:true,timeout:3), [])
      session.up
      session.up detached:true, timeout:3
    end
  end

  describe '#rm' do
    it 'removes containers' do
      expect(shell).to receive(:run).with('docker-compose', 'rm', {}, [])
      expect(shell).to receive(:run).with('docker-compose', 'rm', {}, ['joebob'])
      expect(shell).to receive(:run).with('docker-compose', 'rm', hash_including(f:true,v:true), [])
      session.rm
      session.rm 'joebob'
      session.rm force:true,volumes:true
    end
  end

  describe '#port' do
    context 'given a running service' do
      let(:output) { "0.0.0.0:32769\n" }
      it 'maps ports' do
        expect(session.port('svc1', 8080)).to eq('0.0.0.0:32769')
      end
    end

    context 'given a stopped service' do
      let(:output) { "\n" }
      it 'returns nil' do
        expect(session.port('svc1', 8080)).to eq(nil)
      end
    end
  end

  describe '#run!' do
    it 'omits "--file" when possible' do
      fancypants = described_class.new(shell, file:'docker-compose.yml')
      expect(shell).to receive(:run).with('docker-compose', 'foo')
      fancypants.instance_eval { run!('foo') }
    end

    it 'handles file overrides' do
      fancypants = described_class.new(shell, file:'docker-decompose.yml')
      expect(shell).to receive(:run).with('docker-compose', {file: 'docker-decompose.yml'}, 'foo')
      fancypants.instance_eval { run!('foo') }
    end

    it 'handles multiple files' do
      fancypants = described_class.new(shell, file:['orange.yml', 'apple.yml'])
      expect(shell).to receive(:run).with('docker-compose', {file: 'orange.yml'}, {file: 'apple.yml'}, 'foo')
      fancypants.instance_eval { run!('foo') }
    end

    it 'handles weird input' do
      fancypants = described_class.new(shell, file:42)
      expect(shell).to receive(:run).with('docker-compose', {file: '42'}, 'foo')
      fancypants.instance_eval { run!('foo') }

      fancypants = described_class.new(shell, file:Pathname.new('/tmp/moo.yml'))
      expect(shell).to receive(:run).with('docker-compose', {file: '/tmp/moo.yml'}, 'foo')
      fancypants.instance_eval { run!('foo') }
    end
  end
end
