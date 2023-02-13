# frozen_string_literal: true

module GPS_PVT
  VERSION = "0.9.2"
  
  def GPS_PVT.version_compare(a, b)
    Gem::Version::new(a) <=> Gem::Version::new(b)
  end
end
