describe Docker::Compose::Mapper do
  let(:session) { double('compose session') }
  let(:net_info) { double('net info') }

  let(:env) { {'DB_HOST' => 'service:1234'} }
  subject { described_class.new(session, net_info) }

  it 'maps' do
    allow(session).to receive(:port).with('service', '1234').and_return('0.0.0.0:32154')
    expect(subject.map('http://service:1234')).to eq('http://0.0.0.0:32154')
    expect(subject.map('service:1234')).to eq('0.0.0.0:32154')
    expect(subject.map('service:[1234]')).to eq('0.0.0.0')
    expect(subject.map('[service]:1234')).to eq('32154')
    expect(lambda {
      subject.map(':::::')
    }).to raise_error

    expect(lambda {
      subject.map('notreallyaservice:8080')
    }).to raise_error

    described_class.map(env, session:session, net_info:net_info) do |k, v|
      expect(k).to eq('DB_HOST')
      expect(v).to eq('0.0.0.0:32154')
    end
  end
end