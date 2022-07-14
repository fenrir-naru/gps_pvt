require 'open-uri'
require 'tempfile'
require 'uri'

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
