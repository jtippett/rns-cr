require "../spec_helper"

describe RNS::Rnid do
  describe ".version_string" do
    it "includes rnid and version number" do
      str = RNS::Rnid.version_string
      str.should contain("rnid")
      str.should contain(RNS::VERSION)
    end
  end

  describe ".parse_args" do
    it "returns defaults with no arguments" do
      args = RNS::Rnid.parse_args([] of String)
      args.config.should be_nil
      args.identity.should be_nil
      args.generate.should be_nil
      args.import_str.should be_nil
      args.export.should be_false
      args.verbose.should eq 0
      args.quiet.should eq 0
      args.announce.should be_nil
      args.hash_aspects.should be_nil
      args.encrypt.should be_nil
      args.decrypt.should be_nil
      args.sign.should be_nil
      args.validate.should be_nil
      args.read.should be_nil
      args.write.should be_nil
      args.force.should be_false
      args.stdin.should be_false
      args.stdout.should be_false
      args.request.should be_false
      args.print_identity.should be_false
      args.print_private.should be_false
      args.base64.should be_false
      args.base32.should be_false
      args.version.should be_false
    end

    it "parses --config option" do
      args = RNS::Rnid.parse_args(["--config", "/tmp/test"])
      args.config.should eq "/tmp/test"
    end

    it "parses --version flag" do
      args = RNS::Rnid.parse_args(["--version"])
      args.version.should be_true
    end

    it "parses -i / --identity option" do
      args = RNS::Rnid.parse_args(["-i", "abcdef0123456789abcdef0123456789"])
      args.identity.should eq "abcdef0123456789abcdef0123456789"

      args2 = RNS::Rnid.parse_args(["--identity", "/path/to/id"])
      args2.identity.should eq "/path/to/id"
    end

    it "parses -g / --generate option" do
      args = RNS::Rnid.parse_args(["-g", "/tmp/new_identity"])
      args.generate.should eq "/tmp/new_identity"

      args2 = RNS::Rnid.parse_args(["--generate", "/tmp/id2"])
      args2.generate.should eq "/tmp/id2"
    end

    it "parses -m / --import option" do
      args = RNS::Rnid.parse_args(["-m", "deadbeef"])
      args.import_str.should eq "deadbeef"

      args2 = RNS::Rnid.parse_args(["--import", "cafebabe"])
      args2.import_str.should eq "cafebabe"
    end

    it "parses -x / --export flag" do
      args = RNS::Rnid.parse_args(["-x"])
      args.export.should be_true

      args2 = RNS::Rnid.parse_args(["--export"])
      args2.export.should be_true
    end

    it "parses -v for verbosity" do
      args = RNS::Rnid.parse_args(["-v"])
      args.verbose.should eq 1
    end

    it "parses multiple -v flags" do
      args = RNS::Rnid.parse_args(["-v", "-v", "-v"])
      args.verbose.should eq 3
    end

    it "parses -q for quietness" do
      args = RNS::Rnid.parse_args(["-q"])
      args.quiet.should eq 1
    end

    it "parses combined -vvq flags" do
      args = RNS::Rnid.parse_args(["-vvq"])
      args.verbose.should eq 2
      args.quiet.should eq 1
    end

    it "parses -a / --announce option" do
      args = RNS::Rnid.parse_args(["-a", "myapp.echo"])
      args.announce.should eq "myapp.echo"

      args2 = RNS::Rnid.parse_args(["--announce", "test.service"])
      args2.announce.should eq "test.service"
    end

    it "parses -H / --hash option" do
      args = RNS::Rnid.parse_args(["-H", "myapp.echo"])
      args.hash_aspects.should eq "myapp.echo"

      args2 = RNS::Rnid.parse_args(["--hash", "test.service"])
      args2.hash_aspects.should eq "test.service"
    end

    it "parses -e / --encrypt option" do
      args = RNS::Rnid.parse_args(["-e", "/tmp/file.txt"])
      args.encrypt.should eq "/tmp/file.txt"

      args2 = RNS::Rnid.parse_args(["--encrypt", "/tmp/data"])
      args2.encrypt.should eq "/tmp/data"
    end

    it "parses -d / --decrypt option" do
      args = RNS::Rnid.parse_args(["-d", "/tmp/file.rfe"])
      args.decrypt.should eq "/tmp/file.rfe"

      args2 = RNS::Rnid.parse_args(["--decrypt", "/tmp/data.rfe"])
      args2.decrypt.should eq "/tmp/data.rfe"
    end

    it "parses -s / --sign option" do
      args = RNS::Rnid.parse_args(["-s", "/tmp/file.txt"])
      args.sign.should eq "/tmp/file.txt"

      args2 = RNS::Rnid.parse_args(["--sign", "/tmp/doc"])
      args2.sign.should eq "/tmp/doc"
    end

    it "parses -V / --validate option" do
      args = RNS::Rnid.parse_args(["-V", "/tmp/file.rsg"])
      args.validate.should eq "/tmp/file.rsg"

      args2 = RNS::Rnid.parse_args(["--validate", "/tmp/sig"])
      args2.validate.should eq "/tmp/sig"
    end

    it "parses -r / --read option" do
      args = RNS::Rnid.parse_args(["-r", "/tmp/input"])
      args.read.should eq "/tmp/input"

      args2 = RNS::Rnid.parse_args(["--read", "/tmp/in2"])
      args2.read.should eq "/tmp/in2"
    end

    it "parses -w / --write option" do
      args = RNS::Rnid.parse_args(["-w", "/tmp/output"])
      args.write.should eq "/tmp/output"

      args2 = RNS::Rnid.parse_args(["--write", "/tmp/out2"])
      args2.write.should eq "/tmp/out2"
    end

    it "parses -f / --force flag" do
      args = RNS::Rnid.parse_args(["-f"])
      args.force.should be_true

      args2 = RNS::Rnid.parse_args(["--force"])
      args2.force.should be_true
    end

    it "parses -R / --request flag" do
      args = RNS::Rnid.parse_args(["-R"])
      args.request.should be_true

      args2 = RNS::Rnid.parse_args(["--request"])
      args2.request.should be_true
    end

    it "parses -t timeout option" do
      args = RNS::Rnid.parse_args(["-t", "30.0"])
      args.timeout.should eq 30.0
    end

    it "parses -p / --print-identity flag" do
      args = RNS::Rnid.parse_args(["-p"])
      args.print_identity.should be_true

      args2 = RNS::Rnid.parse_args(["--print-identity"])
      args2.print_identity.should be_true
    end

    it "parses -P / --print-private flag" do
      args = RNS::Rnid.parse_args(["-P"])
      args.print_private.should be_true

      args2 = RNS::Rnid.parse_args(["--print-private"])
      args2.print_private.should be_true
    end

    it "parses -b / --base64 flag" do
      args = RNS::Rnid.parse_args(["-b"])
      args.base64.should be_true

      args2 = RNS::Rnid.parse_args(["--base64"])
      args2.base64.should be_true
    end

    it "parses -B / --base32 flag" do
      args = RNS::Rnid.parse_args(["-B"])
      args.base32.should be_true

      args2 = RNS::Rnid.parse_args(["--base32"])
      args2.base32.should be_true
    end

    it "parses -I / --stdin flag" do
      args = RNS::Rnid.parse_args(["-I"])
      args.stdin.should be_true
    end

    it "parses -O / --stdout flag" do
      args = RNS::Rnid.parse_args(["-O"])
      args.stdout.should be_true
    end

    it "parses combined boolean flags" do
      args = RNS::Rnid.parse_args(["-fRpPbx"])
      args.force.should be_true
      args.request.should be_true
      args.print_identity.should be_true
      args.print_private.should be_true
      args.base64.should be_true
      args.export.should be_true
    end

    it "raises on unknown argument" do
      expect_raises(ArgumentError) do
        RNS::Rnid.parse_args(["--unknown"])
      end
    end

    it "raises on missing --identity value" do
      expect_raises(ArgumentError) do
        RNS::Rnid.parse_args(["--identity"])
      end
    end

    it "raises on missing --generate value" do
      expect_raises(ArgumentError) do
        RNS::Rnid.parse_args(["--generate"])
      end
    end

    it "raises on missing --import value" do
      expect_raises(ArgumentError) do
        RNS::Rnid.parse_args(["--import"])
      end
    end

    it "raises on unexpected positional argument" do
      expect_raises(ArgumentError) do
        RNS::Rnid.parse_args(["some_positional"])
      end
    end
  end

  describe ".usage_string" do
    it "contains usage information" do
      usage = RNS::Rnid.usage_string
      usage.should contain("Reticulum Identity")
      usage.should contain("--config")
      usage.should contain("--identity")
      usage.should contain("--generate")
      usage.should contain("--import")
      usage.should contain("--export")
      usage.should contain("--encrypt")
      usage.should contain("--decrypt")
      usage.should contain("--sign")
      usage.should contain("--validate")
    end
  end

  describe ".encode_key" do
    it "encodes in hex by default" do
      args = RNS::Rnid::Args.new
      data = Bytes[0xAB, 0xCD, 0xEF, 0x01]
      result = RNS::Rnid.encode_key(data, args)
      result.should eq "abcdef01"
    end

    it "encodes in base64 when requested" do
      args = RNS::Rnid::Args.new(base64: true)
      data = Bytes[0x48, 0x65, 0x6C, 0x6C, 0x6F] # "Hello"
      result = RNS::Rnid.encode_key(data, args)
      # Base64 urlsafe encoding of "Hello"
      result.should_not be_empty
      # Should be valid base64 that decodes back
      decoded = Base64.decode(result)
      decoded.should eq data
    end

    it "encodes in base32 when requested" do
      args = RNS::Rnid::Args.new(base32: true)
      data = Bytes[0x48, 0x65, 0x6C, 0x6C, 0x6F] # "Hello"
      result = RNS::Rnid.encode_key(data, args)
      result.should_not be_empty
      # Should decode back correctly
      decoded = RNS::Rnid.base32_decode(result)
      decoded.should eq data
    end
  end

  describe ".base32_encode / .base32_decode" do
    it "roundtrips empty bytes" do
      data = Bytes.empty
      encoded = RNS::Rnid.base32_encode(data)
      decoded = RNS::Rnid.base32_decode(encoded)
      decoded.should eq data
    end

    it "roundtrips single byte" do
      data = Bytes[0xFF]
      encoded = RNS::Rnid.base32_encode(data)
      decoded = RNS::Rnid.base32_decode(encoded)
      decoded.should eq data
    end

    it "roundtrips 'Hello'" do
      data = "Hello".to_slice
      encoded = RNS::Rnid.base32_encode(data)
      encoded.should eq "JBSWY3DP"
      decoded = RNS::Rnid.base32_decode(encoded)
      decoded.should eq data
    end

    it "roundtrips random data" do
      100.times do
        size = Random.rand(1..64)
        data = Random::Secure.random_bytes(size)
        encoded = RNS::Rnid.base32_encode(data)
        decoded = RNS::Rnid.base32_decode(encoded)
        decoded.should eq data
      end
    end

    it "raises on invalid base32 characters" do
      expect_raises(ArgumentError) do
        RNS::Rnid.base32_decode("0189!@#$")
      end
    end
  end

  describe ".decode_import" do
    it "decodes hex format by default" do
      args = RNS::Rnid::Args.new
      result = RNS::Rnid.decode_import("abcdef01", args)
      result.should eq Bytes[0xAB, 0xCD, 0xEF, 0x01]
    end

    it "decodes base64 format" do
      args = RNS::Rnid::Args.new(base64: true)
      original = Bytes[0x48, 0x65, 0x6C, 0x6C, 0x6F]
      encoded = Base64.urlsafe_encode(original)
      result = RNS::Rnid.decode_import(encoded, args)
      result.should eq original
    end

    it "decodes base32 format" do
      args = RNS::Rnid::Args.new(base32: true)
      original = "Hello".to_slice
      encoded = RNS::Rnid.base32_encode(original)
      result = RNS::Rnid.decode_import(encoded, args)
      result.should eq original
    end
  end

  describe "identity operations" do
    it "generates an identity and signs/verifies data" do
      identity = RNS::Identity.new
      identity.prv.should_not be_nil
      identity.pub.should_not be_nil

      message = "Hello, RNS!".to_slice
      signature = identity.sign(message)
      signature.size.should eq 64 # Ed25519 signature length

      identity.validate(signature, message).should be_true
      identity.validate(signature, "Wrong message".to_slice).should be_false
    end

    it "encrypts and decrypts data with identity" do
      identity = RNS::Identity.new
      plaintext = "Secret message for encryption".to_slice

      ciphertext = identity.encrypt(plaintext)
      ciphertext.should_not eq plaintext
      ciphertext.size.should be > plaintext.size

      decrypted = identity.decrypt(ciphertext)
      decrypted.should_not be_nil
      decrypted.not_nil!.should eq plaintext
    end

    it "serializes and deserializes identity" do
      identity = RNS::Identity.new
      prv_key = identity.get_private_key

      restored = RNS::Identity.from_bytes(prv_key)
      restored.should_not be_nil
      restored.not_nil!.get_public_key.should eq identity.get_public_key
    end

    it "saves and loads identity from file" do
      identity = RNS::Identity.new
      tmp_path = File.tempname("rnid_test", ".id")

      begin
        identity.to_file(tmp_path)
        File.exists?(tmp_path).should be_true

        loaded = RNS::Identity.from_file(tmp_path)
        loaded.should_not be_nil
        loaded.not_nil!.get_public_key.should eq identity.get_public_key
        loaded.not_nil!.get_private_key.should eq identity.get_private_key
      ensure
        File.delete(tmp_path) if File.exists?(tmp_path)
      end
    end

    it "sign then verify roundtrip via files" do
      identity = RNS::Identity.new
      tmp_data = File.tempname("rnid_data", ".txt")
      tmp_sig = File.tempname("rnid_sig", ".rsg")

      begin
        # Write test data
        test_data = "This is test data for signing"
        File.write(tmp_data, test_data)

        # Sign the data
        data = File.read(tmp_data).to_slice
        signature = identity.sign(data)
        File.write(tmp_sig, signature)

        # Verify the signature
        sig_data = File.read(tmp_sig).to_slice
        file_data = File.read(tmp_data).to_slice
        identity.validate(sig_data, file_data).should be_true
      ensure
        File.delete(tmp_data) if File.exists?(tmp_data)
        File.delete(tmp_sig) if File.exists?(tmp_sig)
      end
    end

    it "encrypt then decrypt roundtrip via files" do
      identity = RNS::Identity.new
      tmp_plain = File.tempname("rnid_plain", ".txt")
      tmp_enc = File.tempname("rnid_enc", ".rfe")

      begin
        # Write test data
        test_data = "This is confidential data for encryption"
        File.write(tmp_plain, test_data)

        # Encrypt the data
        data = File.read(tmp_plain).to_slice
        encrypted = identity.encrypt(data)
        File.write(tmp_enc, encrypted)

        # Decrypt the data
        enc_data = File.read(tmp_enc).to_slice
        decrypted = identity.decrypt(enc_data)
        decrypted.should_not be_nil
        String.new(decrypted.not_nil!).should eq test_data
      ensure
        File.delete(tmp_plain) if File.exists?(tmp_plain)
        File.delete(tmp_enc) if File.exists?(tmp_enc)
      end
    end
  end

  describe ".parse_args --qr flag" do
    it "parses -Q flag" do
      args = RNS::Rnid.parse_args(["-Q"])
      args.qr.should be_true
    end

    it "parses --qr flag" do
      args = RNS::Rnid.parse_args(["--qr"])
      args.qr.should be_true
    end

    it "defaults qr to false" do
      args = RNS::Rnid.parse_args([] of String)
      args.qr.should be_false
    end

    it "parses combined flags including Q" do
      args = RNS::Rnid.parse_args(["-pQ"])
      args.print_identity.should be_true
      args.qr.should be_true
    end
  end

  describe ".generate_qr_text" do
    it "generates non-empty QR text for a hex string" do
      qr = RNS::Rnid.generate_qr_text("abcdef0123456789abcdef0123456789")
      qr.should_not be_empty
      qr.should contain("\u2588")
      qr.lines.size.should be > 10
    end

    it "generates QR code with consistent dimensions" do
      qr = RNS::Rnid.generate_qr_text("1234567890abcdef1234567890abcdef")
      lines = qr.lines
      lines.size.should be > 0
      # All lines should have the same width (QR codes are square + quiet zone)
      widths = lines.map(&.size).uniq
      widths.size.should eq 1
    end

    it "generates different QR codes for different inputs" do
      qr1 = RNS::Rnid.generate_qr_text("aaaa0000bbbb1111cccc2222dddd3333")
      qr2 = RNS::Rnid.generate_qr_text("1111222233334444555566667777888")
      qr1.should_not eq qr2
    end

    it "handles short input strings" do
      qr = RNS::Rnid.generate_qr_text("hello")
      qr.should_not be_empty
    end
  end

  describe "constants" do
    it "has correct SIG_EXT" do
      RNS::Rnid::SIG_EXT.should eq "rsg"
    end

    it "has correct ENCRYPT_EXT" do
      RNS::Rnid::ENCRYPT_EXT.should eq "rfe"
    end

    it "has correct CHUNK_SIZE" do
      RNS::Rnid::CHUNK_SIZE.should eq 16 * 1024 * 1024
    end

    it "has correct APP_NAME" do
      RNS::Rnid::APP_NAME.should eq "rnid"
    end
  end

  describe "stress tests" do
    it "parses 22 argument combinations" do
      combos = [
        [] of String,
        ["--version"],
        ["-i", "abcdef0123456789abcdef0123456789"],
        ["-g", "/tmp/id"],
        ["-m", "deadbeef"],
        ["-x"],
        ["-v"],
        ["-vvq"],
        ["-a", "myapp.echo"],
        ["-H", "myapp.echo"],
        ["-e", "/tmp/file"],
        ["-d", "/tmp/file.rfe"],
        ["-s", "/tmp/file"],
        ["-V", "/tmp/file.rsg"],
        ["-r", "/tmp/input", "-w", "/tmp/output"],
        ["-f", "-R", "-p", "-P"],
        ["-b", "-i", "abcdef0123456789abcdef0123456789"],
        ["-B", "-i", "abcdef0123456789abcdef0123456789"],
        ["--config", "/tmp/rns", "-i", "/tmp/id", "-p"],
        ["-t", "30.0", "-i", "abcdef0123456789abcdef0123456789", "-R"],
        ["-Q", "-i", "abcdef0123456789abcdef0123456789"],
        ["--qr", "-i", "abcdef0123456789abcdef0123456789"],
      ]

      combos.each do |combo|
        args = RNS::Rnid.parse_args(combo)
        args.should be_a(RNS::Rnid::Args)
      end
    end

    it "base32 roundtrip on various sizes" do
      [0, 1, 2, 3, 4, 5, 8, 16, 32, 64, 128, 256].each do |size|
        data = Random::Secure.random_bytes(size)
        encoded = RNS::Rnid.base32_encode(data)
        decoded = RNS::Rnid.base32_decode(encoded)
        decoded.should eq data
      end
    end
  end
end
