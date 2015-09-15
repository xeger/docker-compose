require 'spec_helper'

describe Docker::Compose do
  it 'has a version number' do
    expect(Docker::Compose::VERSION).not_to be nil
  end

  describe '.new' do
    subject { described_class }

    it 'makes a session' do
      meth = Docker::Compose::Session.instance_methods -
        Docker::Compose::Session.superclass.instance_methods
      s1 = subject.new
      meth.each { |m| expect(s1).to respond_to m }
      s2 = subject.new
      expect(s1).not_to be(s2)
    end
  end
end
