require "./spec_helper"

describe RNS do
  it "has a version" do
    RNS::VERSION.should_not be_nil
    RNS::VERSION.should eq "0.1.0"
  end

  it "returns version via module method" do
    RNS.version.should eq "0.1.0"
  end
end
