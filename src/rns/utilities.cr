module RNS
  def self.hexrep(data : Bytes, delimit : Bool = true) : String
    delimiter = delimit ? ":" : ""
    data.join(delimiter) { |byte| "%02x" % byte }
  end

  def self.prettyhexrep(data : Bytes) : String
    "<#{data.join("") { |byte| "%02x" % byte }}>"
  end

  def self.prettyspeed(num : Float64, suffix : String = "b") : String
    prettysize(num / 8, suffix: suffix) + "ps"
  end

  def self.prettysize(num : Float64, suffix : String = "B") : String
    units = ["", "K", "M", "G", "T", "P", "E", "Z"]
    last_unit = "Y"

    if suffix == "b"
      num = num * 8
    end

    units.each do |unit|
      if num.abs < 1000.0
        if unit == ""
          return "%.0f %s%s" % [num, unit, suffix]
        else
          return "%.2f %s%s" % [num, unit, suffix]
        end
      end
      num /= 1000.0
    end

    "%.2f%s%s" % [num, last_unit, suffix]
  end

  def self.prettyfrequency(hz : Float64, suffix : String = "Hz") : String
    num = hz * 1e6
    units = ["µ", "m", "", "K", "M", "G", "T", "P", "E", "Z"]
    last_unit = "Y"

    units.each do |unit|
      if num.abs < 1000.0
        return "%.2f %s%s" % [num, unit, suffix]
      end
      num /= 1000.0
    end

    "%.2f%s%s" % [num, last_unit, suffix]
  end

  def self.prettydistance(m : Float64, suffix : String = "m") : String
    num = m * 1e6
    units = ["µ", "m", "c", ""]
    last_unit = "K"

    units.each do |unit|
      divisor = 1000.0
      divisor = 10.0 if unit == "m"
      divisor = 100.0 if unit == "c"

      if num.abs < divisor
        return "%.2f %s%s" % [num, unit, suffix]
      end
      num /= divisor
    end

    "%.2f %s%s" % [num, last_unit, suffix]
  end

  def self.prettytime(time : Float64, verbose : Bool = false, compact : Bool = false) : String
    neg = false
    if time < 0
      time = time.abs
      neg = true
    end

    days = (time / (24 * 3600)).to_i
    time = time % (24 * 3600)
    hours = (time / 3600).to_i
    time = time % 3600
    minutes = (time / 60).to_i
    time = time % 60

    seconds = if compact
                time.to_i
              else
                (time * 100).round / 100
              end

    ss = seconds == 1 ? "" : "s"
    sm = minutes == 1 ? "" : "s"
    sh = hours == 1 ? "" : "s"
    sd = days == 1 ? "" : "s"

    displayed = 0
    components = [] of String

    if days > 0 && (!compact || displayed < 2)
      components << (verbose ? "#{days} day#{sd}" : "#{days}d")
      displayed += 1
    end

    if hours > 0 && (!compact || displayed < 2)
      components << (verbose ? "#{hours} hour#{sh}" : "#{hours}h")
      displayed += 1
    end

    if minutes > 0 && (!compact || displayed < 2)
      components << (verbose ? "#{minutes} minute#{sm}" : "#{minutes}m")
      displayed += 1
    end

    if seconds > 0 && (!compact || displayed < 2)
      components << (verbose ? "#{seconds} second#{ss}" : "#{seconds}s")
      displayed += 1
    end

    tstr = ""
    components.each_with_index do |c, i|
      if i == 0
        # first component, no prefix
      elsif i < components.size - 1
        tstr += ", "
      else
        tstr += " and "
      end
      tstr += c
    end

    if tstr.empty?
      "0s"
    elsif neg
      "-#{tstr}"
    else
      tstr
    end
  end

  def self.prettyshorttime(time : Float64, verbose : Bool = false, compact : Bool = false) : String
    neg = false
    time = time * 1e6
    if time < 0
      time = time.abs
      neg = true
    end

    seconds = (time / 1e6).to_i
    time = time % 1e6
    milliseconds = (time / 1e3).to_i
    time = time % 1e3

    microseconds = if compact
                     time.to_i
                   else
                     (time * 100).round / 100
                   end

    ss = seconds == 1 ? "" : "s"
    sms = milliseconds == 1 ? "" : "s"
    sus = microseconds == 1 ? "" : "s"

    displayed = 0
    components = [] of String

    if seconds > 0 && (!compact || displayed < 2)
      components << (verbose ? "#{seconds} second#{ss}" : "#{seconds}s")
      displayed += 1
    end

    if milliseconds > 0 && (!compact || displayed < 2)
      components << (verbose ? "#{milliseconds} millisecond#{sms}" : "#{milliseconds}ms")
      displayed += 1
    end

    if microseconds > 0 && (!compact || displayed < 2)
      components << (verbose ? "#{microseconds} microsecond#{sus}" : "#{microseconds}µs")
      displayed += 1
    end

    tstr = ""
    components.each_with_index do |c, i|
      if i == 0
        # first component, no prefix
      elsif i < components.size - 1
        tstr += ", "
      else
        tstr += " and "
      end
      tstr += c
    end

    if tstr.empty?
      "0us"
    elsif neg
      "-#{tstr}"
    else
      tstr
    end
  end
end
