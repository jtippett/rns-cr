module RNS
  module PlatformUtils
    def self.get_platform : String
      if ENV.has_key?("ANDROID_ARGUMENT") || ENV.has_key?("ANDROID_ROOT")
        "android"
      else
        {% if flag?(:linux) %}
          "linux"
        {% elsif flag?(:darwin) %}
          "darwin"
        {% elsif flag?(:win32) %}
          "windows"
        {% elsif flag?(:freebsd) %}
          "freebsd"
        {% elsif flag?(:openbsd) %}
          "openbsd"
        {% else %}
          "unknown"
        {% end %}
      end
    end

    def self.is_linux? : Bool
      get_platform == "linux"
    end

    def self.is_darwin? : Bool
      get_platform == "darwin"
    end

    def self.is_android? : Bool
      get_platform == "android"
    end

    def self.is_windows? : Bool
      get_platform.starts_with?("win")
    end

    def self.use_epoll? : Bool
      is_linux? || is_android?
    end

    def self.use_af_unix? : Bool
      is_linux? || is_android?
    end
  end
end
