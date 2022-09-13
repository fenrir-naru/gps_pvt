require 'tempfile'
require 'uri'

proc{
  # port[:baudrate], baudrate default is 115200
  Serial.class_eval{
    const_set(:SPEC, 
        if RubySerial::ON_WINDOWS then
          %r{^(?:\\\\.\\)?(COM\d+)(?::(\d+))?$}
        elsif RubySerial::ON_LINUX then
          %r{^(/dev/tty[^:]+)(?::(\d+))?$}
        else
          nil
        end)
  }
  Serial.class_eval{
    read_orig = instance_method(:read)
    define_method(:read){|len|
      buf = ''
      f = read_orig.bind(self)
      buf += f.call(len - buf.size) while buf.size < len
      buf
    }
    def eof?; false; end
  }
  Kernel.instance_eval{
    open_orig = method(:open)
    define_method(:open){|*args, &b|
      return open_orig.call(*args, &b) unless Serial::SPEC =~ args[0]
      Serial::new($1, $2 ? $2.to_i : 115200)
    }
  }
}.call if require 'rubyserial'

require 'open-uri'

module GPS_PVT
module Util
  class << self
    def inflate(src, type = :gz)
      case type
      when :gz
        require 'zlib'
        Zlib::GzipReader.send(*(src.kind_of?(IO) ? [:new, src] : [:open, src]))
      when :Z
        res = IO::popen("uncompress -c #{src.kind_of?(IO) ? '-' : src}", 'r+')
        res.print(src.read) if src.kind_of?(IO)
        res.close_write
        res
      else
        raise "Unknown compression type: #{type} of #{src}"
      end
    end
    def get_txt(fname_or_uri)
      is_uri = fname_or_uri.kind_of?(URI)
      ((is_uri && (RUBY_VERSION >= "2.5.0")) ? URI : Kernel) \
          .send(:open, fname_or_uri){|src|
        compressed = proc{
          case src.content_type
          when /gzip/; next :gz
          end if is_uri
          case fname_or_uri.to_s
          when /\.gz$/; next :gz
          when /\.Z$/; next :Z
          end
          nil
        }.call
        is_file = src.kind_of?(File) || src.kind_of?(Tempfile)

        return src.path if ((!compressed) and is_file)

        Tempfile::open(File::basename($0, '.*')){|dst|
          dst.binmode
          dst.write((compressed ? inflate(is_file ? src.path : src, compressed) : src).read)
          dst.rewind
          dst.path
        }
      }
    end
  end
end
end
