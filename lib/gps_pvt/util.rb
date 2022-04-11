require 'open-uri'
require 'tempfile'
require 'uri'
require 'zlib'

module GPS_PVT
module Util
  class << self
    def inflate(src)
      Zlib::GzipReader.send(*(src.kind_of?(IO) ? [:new, src] : [:open, src]))
    end
    def get_txt(fname_or_uri)
      is_uri = fname_or_uri.kind_of?(URI)
      ((is_uri && (RUBY_VERSION >= "2.5.0")) ? URI : Kernel) \
          .send(:open, fname_or_uri){|src|
        is_gz = (src.content_type =~ /gzip/) if is_uri
        is_gz ||= (fname_or_uri.to_s =~ /\.gz$/)
        is_file = src.kind_of?(File) || src.kind_of?(Tempfile)

        return src.path if ((!is_gz) and is_file)

        Tempfile::open(File::basename($0, '.*')){|dst|
          dst.binmode
          dst.write((is_gz ? inflate(is_file ? src.path : src) : src).read)
          dst.rewind
          dst.path
        }
      }
    end
  end
end
end
