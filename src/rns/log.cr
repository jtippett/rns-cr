module RNS
  LOG_NONE     = -1
  LOG_CRITICAL =  0
  LOG_ERROR    =  1
  LOG_WARNING  =  2
  LOG_NOTICE   =  3
  LOG_INFO     =  4
  LOG_VERBOSE  =  5
  LOG_DEBUG    =  6
  LOG_EXTREME  =  7

  LOG_STDOUT   = 0x91
  LOG_FILE     = 0x92
  LOG_CALLBACK = 0x93

  LOG_MAXSIZE = 5 * 1024 * 1024

  class_property loglevel : Int32 = LOG_NOTICE
  class_property logfile : String? = nil
  class_property logdest : Int32 = LOG_STDOUT
  class_property logcall : Proc(String, Nil)? = nil
  class_property logtimefmt : String = "%Y-%m-%d %H:%M:%S"
  class_property compact_log_fmt : Bool = false

  @@logging_mutex = Mutex.new
  @@always_override_destination = false

  def self.loglevelname(level : Int32) : String
    case level
    when LOG_CRITICAL then "[Critical]"
    when LOG_ERROR    then "[Error]   "
    when LOG_WARNING  then "[Warning] "
    when LOG_NOTICE   then "[Notice]  "
    when LOG_INFO     then "[Info]    "
    when LOG_VERBOSE  then "[Verbose] "
    when LOG_DEBUG    then "[Debug]   "
    when LOG_EXTREME  then "[Extra]   "
    else                   "Unknown"
    end
  end

  def self.timestamp_str(time_s : Float64) : String
    time = Time.unix(time_s.to_i64)
    time.to_s(@@logtimefmt)
  end

  def self.log(msg, level : Int32 = LOG_NOTICE, _override_destination : Bool = false)
    return if @@loglevel == LOG_NONE
    msg = msg.to_s

    if @@loglevel >= level
      if @@compact_log_fmt
        logstring = "[#{timestamp_str(Time.utc.to_unix_f)}] #{msg}"
      else
        logstring = "[#{timestamp_str(Time.utc.to_unix_f)}] #{loglevelname(level)} #{msg}"
      end

      @@logging_mutex.synchronize do
        if @@logdest == LOG_STDOUT || @@always_override_destination || _override_destination
          puts logstring
        elsif @@logdest == LOG_FILE && @@logfile
          begin
            lf = @@logfile.not_nil!
            File.open(lf, "a") do |file|
              file.puts logstring
            end

            if File.size(lf) > LOG_MAXSIZE
              prevfile = "#{lf}.1"
              File.delete(prevfile) if File.exists?(prevfile)
              File.rename(lf, prevfile)
            end
          rescue ex
            @@always_override_destination = true
            log("Exception occurred while writing log message to log file: #{ex}", LOG_CRITICAL)
            log("Dumping future log events to console!", LOG_CRITICAL)
            log(msg, level)
          end
        elsif @@logdest == LOG_CALLBACK
          begin
            @@logcall.try &.call(logstring)
          rescue ex
            @@always_override_destination = true
            log("Exception occurred while calling external log handler: #{ex}", LOG_CRITICAL)
            log("Dumping future log events to console!", LOG_CRITICAL)
            log(msg, level)
          end
        end
      end
    end
  end

  def self.host_os : String
    PlatformUtils.get_platform
  end

  def self.rand : Float64
    ::Random.rand
  end

  def self.panic
    Process.exit(255)
  end
end
