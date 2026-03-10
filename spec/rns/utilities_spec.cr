require "../spec_helper"

describe RNS do
  describe ".hexrep" do
    it "converts bytes to colon-delimited hex" do
      data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      RNS.hexrep(data).should eq("de:ad:be:ef")
    end

    it "converts bytes without delimiter when delimit is false" do
      data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      RNS.hexrep(data, delimit: false).should eq("deadbeef")
    end

    it "handles empty bytes" do
      data = Bytes.empty
      RNS.hexrep(data).should eq("")
    end

    it "handles single byte" do
      data = Bytes[0x0A]
      RNS.hexrep(data).should eq("0a")
    end

    it "pads single-digit hex values with zero" do
      data = Bytes[0x01, 0x02, 0x03]
      RNS.hexrep(data).should eq("01:02:03")
    end
  end

  describe ".prettyhexrep" do
    it "wraps hex in angle brackets without delimiters" do
      data = Bytes[0xDE, 0xAD, 0xBE, 0xEF]
      RNS.prettyhexrep(data).should eq("<deadbeef>")
    end

    it "handles empty bytes" do
      data = Bytes.empty
      RNS.prettyhexrep(data).should eq("<>")
    end
  end

  describe ".prettysize" do
    it "formats bytes" do
      RNS.prettysize(100.0).should eq("100 B")
    end

    it "formats kilobytes" do
      RNS.prettysize(1500.0).should eq("1.50 KB")
    end

    it "formats megabytes" do
      RNS.prettysize(1_500_000.0).should eq("1.50 MB")
    end

    it "formats gigabytes" do
      RNS.prettysize(1_500_000_000.0).should eq("1.50 GB")
    end

    it "handles zero" do
      RNS.prettysize(0.0).should eq("0 B")
    end

    it "supports bits suffix" do
      # 125 * 8 = 1000 bits, 1000 >= 1000 threshold so scales to Kb
      RNS.prettysize(125.0, suffix: "b").should eq("1.00 Kb")
    end

    it "formats kilobits" do
      RNS.prettysize(150.0, suffix: "b").should eq("1.20 Kb")
    end
  end

  describe ".prettyspeed" do
    it "formats speed in bits per second" do
      # prettyspeed(8000) → prettysize(1000, suffix: "b") → 1000*8=8000 bits → "8.00 Kb" → "8.00 Kbps"
      result = RNS.prettyspeed(8000.0)
      result.should eq("8.00 Kbps")
    end

    it "formats small speed" do
      # prettyspeed(800) → prettysize(100, suffix: "b") → 100*8=800 bits → "800 b" → "800 bps"
      result = RNS.prettyspeed(800.0)
      result.should eq("800 bps")
    end
  end

  describe ".prettyfrequency" do
    it "formats Hz from small input" do
      # hz=868 → num=868*1e6=868000000 → scales through µ,m → 868 Hz
      result = RNS.prettyfrequency(868.0)
      result.should eq("868.00 Hz")
    end

    it "formats MHz from Hz input" do
      # hz=868e6 → num=868e12 → scales through µ,m,Hz,K → 868 MHz
      result = RNS.prettyfrequency(868_000_000.0)
      result.should eq("868.00 MHz")
    end

    it "formats GHz" do
      result = RNS.prettyfrequency(2_400_000_000.0)
      result.should eq("2.40 GHz")
    end
  end

  describe ".prettydistance" do
    it "formats meters" do
      result = RNS.prettydistance(1.0)
      result.should eq("1.00 m")
    end

    it "formats kilometers" do
      result = RNS.prettydistance(1500.0)
      result.should eq("1.50 Km")
    end

    it "formats millimeters" do
      result = RNS.prettydistance(0.001)
      result.should eq("1.00 mm")
    end
  end

  describe ".prettytime" do
    it "formats zero seconds" do
      RNS.prettytime(0.0).should eq("0s")
    end

    it "formats seconds only" do
      RNS.prettytime(30.0).should eq("30.0s")
    end

    it "formats minutes and seconds" do
      RNS.prettytime(90.0).should eq("1m and 30.0s")
    end

    it "formats hours, minutes and seconds" do
      RNS.prettytime(3661.0).should eq("1h, 1m and 1.0s")
    end

    it "formats days" do
      RNS.prettytime(90061.0).should eq("1d, 1h, 1m and 1.0s")
    end

    it "handles verbose mode" do
      RNS.prettytime(90061.0, verbose: true).should eq("1 day, 1 hour, 1 minute and 1.0 second")
    end

    it "handles verbose plurals" do
      RNS.prettytime(180122.0, verbose: true).should eq("2 days, 2 hours, 2 minutes and 2.0 seconds")
    end

    it "handles compact mode" do
      result = RNS.prettytime(90061.5, compact: true)
      # Compact shows at most 2 components and uses integer seconds
      result.should eq("1d and 1h")
    end

    it "handles negative time" do
      result = RNS.prettytime(-30.0)
      result.should eq("-30.0s")
    end
  end

  describe ".prettyshorttime" do
    it "formats zero" do
      RNS.prettyshorttime(0.0).should eq("0us")
    end

    it "formats seconds" do
      RNS.prettyshorttime(1.5).should eq("1s and 500ms")
    end

    it "formats milliseconds" do
      RNS.prettyshorttime(0.025).should eq("25ms")
    end

    it "formats microseconds" do
      # Python round(50.0, 2) = 50.0, str(50.0) = "50.0"
      RNS.prettyshorttime(0.000050).should eq("50.0µs")
    end

    it "handles negative time" do
      result = RNS.prettyshorttime(-0.025)
      result.should eq("-25ms")
    end
  end
end
