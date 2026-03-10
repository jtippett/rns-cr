require "../../spec_helper"

describe RNS::PlatformUtils do
  describe ".get_platform" do
    it "returns a non-empty string" do
      platform = RNS::PlatformUtils.get_platform
      platform.should_not be_empty
    end

    it "returns a known platform on this system" do
      platform = RNS::PlatformUtils.get_platform
      # Should be one of the known platforms
      ["linux", "darwin", "windows", "android", "freebsd", "openbsd"].should contain(platform)
    end
  end

  describe ".is_linux?" do
    it "returns a Bool" do
      RNS::PlatformUtils.is_linux?.should be_a(Bool)
    end
  end

  describe ".is_darwin?" do
    it "returns a Bool" do
      RNS::PlatformUtils.is_darwin?.should be_a(Bool)
    end

    {% if flag?(:darwin) %}
      it "returns true on macOS" do
        RNS::PlatformUtils.is_darwin?.should be_true
      end
    {% end %}
  end

  describe ".is_android?" do
    it "returns a Bool" do
      RNS::PlatformUtils.is_android?.should be_a(Bool)
    end
  end

  describe ".is_windows?" do
    it "returns a Bool" do
      RNS::PlatformUtils.is_windows?.should be_a(Bool)
    end
  end

  describe ".use_epoll?" do
    it "returns true only on linux/android" do
      if RNS::PlatformUtils.is_linux? || RNS::PlatformUtils.is_android?
        RNS::PlatformUtils.use_epoll?.should be_true
      else
        RNS::PlatformUtils.use_epoll?.should be_false
      end
    end
  end

  describe ".use_af_unix?" do
    it "returns true only on linux/android" do
      if RNS::PlatformUtils.is_linux? || RNS::PlatformUtils.is_android?
        RNS::PlatformUtils.use_af_unix?.should be_true
      else
        RNS::PlatformUtils.use_af_unix?.should be_false
      end
    end
  end
end
