describe Docker::Compose::Session do
  let(:shell) { double('shell', :interactive => false, :"interactive=" => true, :"chdir=" => true) }
  subject(:session) { described_class.new(shell) }

  let(:exitstatus) { 0 }
  let(:status) { double('exit status', to_s: "pid 12345 exit #{exitstatus}", to_i: exitstatus) }
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
      expect(shell).to receive(:run).with('docker-compose', 'build', {}, ['alice', 'bob']).once
      session.build('alice', 'bob')
      expect(shell).to receive(:run).with('docker-compose', 'build', {force_rm:true, no_cache:true, pull:true}, []).once
      session.build(force_rm:true, no_cache:true, pull:true)
    end
  end

  describe '#ps' do
    # hashes is overridden in nested contexts.
    let(:hashes) { ['corned_beef'] }

    # output is used by command (defined in top context).
    let(:output) { hashes.join("\n") }

    # Mock some additional calls to run! that the ps method makes in order
    # to get info about each container
    before do
      hashes.each do |h|
        cmd = double('command',
                     status:status,
                     captured_output:"(#{h}) (xeger/#{h}:latest) (1.0MB (virtual 7.3MB)) (Up 1 second) (#{h}) () ()",
                     captured_error:'')
        allow(cmd).to receive(:join).and_return(cmd)
        expect(shell).to receive(:run).with('docker', 'ps', hash_including(f:"id=#{h}")).and_return(cmd)
        allow(shell).to receive(:interactive=)
      end
    end

    it 'reports accurate size' do
      cont = session.ps()
      expect(cont).not_to be_empty
      expect(cont[0].size).to eq(1_048_576)
    end

    context 'given no filter' do
      let(:hashes) { ['corned_beef', 'sweet_potato', 'afghan_black'] }

      it 'lists containers' do
        session.ps
      end
    end

    context 'given a filter' do
      let(:hashes) { ['sweet_potato', 'afghan_black'] }

      it 'lists containers' do
        expect(shell).to receive(:run).with("docker-compose", "ps", hash_including(), ["service1", "service2"])
        expect(shell).not_to receive(:run).with('docker', 'ps', hash_including(f:"id=corned_beef"))
        cont = session.ps('service1', 'service2')
        expect(cont.size).to eq(2)
      end
    end
  end

  describe '#up' do
    it 'runs containers' do
      expect(shell).to receive(:run).with('docker-compose', 'up', {}, [])
      expect(shell).to receive(:run).with('docker-compose', 'up', hash_including(d:true,timeout:3), [])
      expect(shell).to receive(:run).with('docker-compose', 'up', hash_including(no_start:true), [])
      session.up
      session.up detached:true, timeout:3
      session.up no_start:true
    end
  end

  describe '#down' do
    it 'brings down containers' do
      expect(shell).to receive(:run).with('docker-compose', 'down', {})
      expect(shell).to receive(:run).with('docker-compose', 'down', hash_including(v:true))
      session.down
      session.down remove_volumes:true
    end
  end

  describe '#run' do
    it 'runs containers' do
      expect(shell).to receive(:run).with('docker-compose', 'run', {}, 'service1', [])
      expect(shell).to receive(:run).with('docker-compose', 'run', hash_including(d:true,T:true), 'service1', %w(command command_args))
      expect(shell).to receive(:run).with('docker-compose', 'run', hash_including(u:'user_id:group_id'), 'service1', [])
      session.run('service1')
      session.run('service1', 'command', 'command_args', no_tty: true, detached: true)
      session.run('service1', user: 'user_id:group_id')
    end

    it 'runs containers with env vars' do
      expect(shell).to receive(:run).with('docker-compose', 'run', {}, { e:'VAR1=val1' }, 'service1', [])
      session.run('service1', env: ["VAR1=val1"])
      expect(shell).to receive(:run).with('docker-compose', 'run', {}, { e:'VAR1=val1' }, { e:'VAR2=val2'}, 'service1', [])
      session.run('service1', env: ["VAR1=val1", "VAR2=val2"])
    end

    it 'runs containers with mounted volumes' do
      expect(shell).to receive(:run).with('docker-compose', 'run', {}, { v:'/host1:/container1' }, 'service1', [])
      session.run('service1', volumes: ['/host1:/container1'])
      expect(shell).to receive(:run).with('docker-compose', 'run', {}, { v:'/host1:/container1' }, { v:'/host2:/container2' }, 'service1', [])
      session.run('service1', volumes: ['/host1:/container1', '/host2:/container2'])
    end
  end

  describe '#scale' do
    it 'scales containers' do
      expect(shell).to receive(:run).with('docker-compose', 'scale', {}, 'service1=2')
      expect(shell).to receive(:run).with('docker-compose', 'scale', {}, 'service1=3', 'service2=4')
      expect(shell).to receive(:run).with('docker-compose', 'scale', { timeout: 3 }, 'service1=1')
      session.scale(service1: 2)
      session.scale(service1: 3, service2: 4)
      session.scale({ service1: 1 }, timeout: 3)
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
    context 'given color output' do
      let(:output) { "\033[37m0.0.0.0:32769\n" }
      it 'maps ports' do
        expect(session.port('svc1', 8080)).to eq('0.0.0.0:32769')
      end
    end

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
