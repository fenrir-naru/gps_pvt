require_relative 'upl/upl'
require_relative 'GPS'

require 'socket'
require 'openssl'

module GPS_PVT
class SUPL_Client
  include UPL
  
  attr_accessor :opts
  
  def initialize(host, opts = {})
    @host = host
    @opts = {
      :port => 7275,
      :debug => 0,
      :protocol => [:lpp, :rrlp],
      :req_data => [:ephemeris], # :almanac
    }.merge(opts)
  end

  def get_assisted_data
    begin
      @socket = TCPSocket::new(@host, @opts[:port])
      if @opts[:port] == 7275 then
        @socket = OpenSSL::SSL::SSLSocket::new(@socket)
        @socket.connect
      end
      send_supl_start
      recv_supl_response
      send_supl_pos_init
      recv_supl_pos
    ensure
      @socket.close unless @socket.closed?
    end
  end
  
  private

  def send(cmd)
    msg = encode(cmd)
    (iter = proc{|keys, root1, root2, parents|
      keys.each{|k|
        if k.kind_of?(Hash) then
          k.each{|k2, v2|
            iter.call(v2, root1[k2], root2[k2], parents + [k2])
          }
        else
          $stderr.puts [parents + [k], root1[k], root2[k]].inspect unless root1[k] == root2[k]
        end
      }
    }).call(cmd.all_keys - [:length], cmd, decode(msg), []) if @opts[:debug] > 2
    $stderr.puts [
        msg.unpack("C*").collect{|byte| "%02X"%[byte]}.join(' '),
        decode(msg)].inspect if @opts[:debug] > 1
    $stderr.puts "tx(#{msg.size})" if @opts[:debug] > 0
    @socket.write(msg)
  end

  def receive
    raw = @socket.read(2)
    raw += @socket.read(raw.unpack("n")[0] - 2)
    res = decode(raw)
    $stderr.puts "rx(#{raw.size})" if @opts[:debug] > 0
    $stderr.puts [raw, res] if @opts[:debug] > 1
    res
  end

  def send_supl_start
    cmd = generate_skeleton(:SUPLSTART, {:version => 2})
    cmd[:sessionID][:setSessionID] = {
      :sessionId => 1,
      :setId => proc{
        # Ex) :msisdn => [0xFF, 0xFF, 0x91, 0x94, 0x48, 0x45, 0x83, 0x98],
        next {:msisdn => @opts[:msisdn]} if @opts[:msisdn]
        # Ex) :imsi => "440109012345678",
        next {:imsi => @opts[:imsi].scan(/(.)(.?)/).collect{|a, b|
          "0x#{a}#{b == '' ? '0' : b}".to_i(16)
        }} if @opts[:imsi]
        require 'resolv'
        remote_ip = Resolv::DNS.new({:nameserver => "resolver1.opendns.com"}) \
            .getresources("myip.opendns.com", Resolv::DNS::Resource::IN::A)[0].address
        {:iPAddress => case remote_ip
        when Resolv::IPv4; {:ipv4Address => remote_ip.address.unpack("C4")}
        when Resolv::IPv6; {:ipv6Address => remote_ip.address.unpack("C16")}
        else; raise
        end}
      }.call
    }
    proc{|cap|
      cap[:posTechnology].keys.each{|k|
        cap[:posTechnology][k] = [:agpsSETBased].include?(k)
      }
      cap[:posTechnology][:"ver2-PosTechnology-extension"] = {
        :gANSSPositionMethods => [
          {
            :ganssId => 1, # SBAS
            :ganssSBASid => [0, 1, 0], # MSAS
            :gANSSPositioningMethodTypes => {:setAssisted => true, :setBased => true, :autonomous => false},
            :gANSSSignals => [1] * 8,
          },
          {
            :ganssId => 3, # QZSS
            :gANSSPositioningMethodTypes => {:setAssisted => true, :setBased => true, :autonomous => false},
            :gANSSSignals => [1] * 8,
          },
          {
            :ganssId => 4, # GLONASS
            :gANSSPositioningMethodTypes => {:setAssisted => true, :setBased => true, :autonomous => false},
            :gANSSSignals => [1] * 8,
          },
        ],
      }
      cap[:prefMethod] = :agpsSETBasedPreferred
      cap[:posProtocol].keys.each{|k|
        cap[:posProtocol][k] = [:rrlp].include?(k)
      }
      cap[:posProtocol][:"ver2-PosProtocol-extension"] = {
        :lpp => @opts[:protocol].include?(:lpp),
        :posProtocolVersionRRLP => {
          :majorVersionField => 17,
          :technicalVersionField => 0,
          :editorialVersionField => 0,
        },
        :posProtocolVersionLPP => {
          :majorVersionField => 17,
          :technicalVersionField => 5,
          :editorialVersionField => 0,
        },
      }
      @capability = cap
    }.call(cmd[:message][:msSUPLSTART][:sETCapabilities])
    proc{|loc|
      loc[:cellInfo] = {
        :gsmCell => {:refMCC => 244, :refMNC => 5, :refLAC => 23010, :refCI => 12720},
      }
      loc[:status] = :current
      @location_id = loc
    }.call(cmd[:message][:msSUPLSTART][:locationId])
      
    send(cmd)
  end
  
  
  def recv_supl_response
    data = receive
    @session_id = data[:sessionID]
  end

  def send_supl_pos_init
    cmd = generate_skeleton(:SUPLPOSINIT, {:version => 2})
    cmd[:sessionID] = @session_id
    proc{|posinit|
      posinit[:sETCapabilities] = @capability
      req_data = [
        @opts[:req_data].find_index(:almanac) && :almanacRequested,
        :utcModelRequested,
        :ionosphericModelRequested,
        :referenceLocationRequested,
        :referenceTimeRequested,
        :acquisitionAssistanceRequested,
        :realTimeIntegrityRequested,
        @opts[:req_data].find_index(:ephemeris) && :navigationModelRequested,
      ].compact
      posinit[:requestedAssistData] = Hash[*([
        :almanacRequested,
        :utcModelRequested,
        :ionosphericModelRequested,
        :dgpsCorrectionsRequested,
        :referenceLocationRequested,
        :referenceTimeRequested,
        :acquisitionAssistanceRequested,
        :realTimeIntegrityRequested,
        :navigationModelRequested,
      ].collect{|k|
        [k, req_data.include?(k)]
      }.flatten(1))]
      posinit[:requestedAssistData][:"ver2-RequestedAssistData-extension"] = {
        :ganssRequestedCommonAssistanceDataList => {
          :ganssReferenceTime => true,
          :ganssIonosphericModel => true,
          :ganssAdditionalIonosphericModelForDataID00 => false,
          :ganssAdditionalIonosphericModelForDataID11 => false,
          :ganssEarthOrientationParameters => false,
          :ganssAdditionalIonosphericModelForDataID01 => false,
        },
        :ganssRequestedGenericAssistanceDataList => [
          # SBAS
          {:ganssId => 1, :ganssSBASid => [0, 1, 0], # MSAS
              :ganssRealTimeIntegrity => true,
              :ganssReferenceMeasurementInfo => false, :ganssUTCModel => true, :ganssAuxiliaryInformation => false},
          # QZSS
          {:ganssId => 3, :ganssRealTimeIntegrity => true,
              :ganssReferenceMeasurementInfo => false, :ganssUTCModel => true, :ganssAuxiliaryInformation => false},
          # GLONASS
          {:ganssId => 4, :ganssRealTimeIntegrity => true,
              :ganssReferenceMeasurementInfo => false, :ganssUTCModel => true, :ganssAuxiliaryInformation => false},
        ].collect{|items|
          items[:ganssAlmanac] = @opts[:req_data].include?(:almanac)
          items[:ganssNavigationModelData] = {
            :ganssWeek => 0, :ganssToe => 0, :"t-toeLimit" => 0
          } if @opts[:req_data].include?(:ephemeris)
          items
        },
      }
      posinit[:requestedAssistData][:navigationModelData] = {
        :gpsWeek => 0,
        :gpsToe => 0,
        :nSAT => 0,
        :toeLimit => 0,
      } if false
      posinit[:locationId] = @location_id
    }.call(cmd[:message][:msSUPLPOSINIT])
    
    send(cmd)
  end

  def recv_supl_pos
    res = {}
    merge = proc{|src, dst|
      src.each{|k, v|
        case dst[k]
        when Hash; merge.call(v, dst[k])
        when Array; dst[k] += v
        when nil; dst[k] = v
        end
      }
    }
    data = receive
    if data[:message][:msSUPLPOS][:posPayLoad][:"ver2-PosPayLoad-extension"] then
      merge.call(
          data[:message][:msSUPLPOS][:posPayLoad][:"ver2-PosPayLoad-extension"][:lPPPayload].decode[:"lpp-MessageBody"],
          res)
      attach_lpp(res)
    else
      while true
        rrlp_data = data[:message][:msSUPLPOS][:posPayLoad][:rrlpPayload].decode
        merge.call(
            rrlp_data[:component][:assistanceData][:"gps-AssistData"][:controlHeader],
            res)
        break unless (rrlp_data[:component][:assistanceData][:moreAssDataToBeSent] == :moreMessagesOnTheWay)
        
        # SUPL-POS + RRLP-assistanceDataAck
        cmd = generate_skeleton(:SUPLPOS, {:version => 2})
        cmd[:sessionID] = @session_id
        cmd[:message][:msSUPLPOS] = {
          :posPayLoad => {:rrlpPayload => {
            :referenceNumber => rrlp_data[:referenceNumber],
            :component => {:assistanceDataAck => nil}
          }}
        }
        send(cmd)
        data = receive
      end
      attach_rrlp(res)
    end
    res
  end
  
  def SUPL_Client.correct_gps_week(week, t_gps_ref, width = 1024)
    width_half = width / 2
    cycle, week_rem_ref = t_gps_ref.week.divmod(width)
    week_rem = week % width
    delta = week_rem_ref - week_rem
    if delta > width_half then
      cycle += 1
    elsif delta < -width_half then
      cycle -= 1
  end
    cycle * width + week_rem
  end
  
  EPH_KEY_TBL_RRLP = Hash[*({
    :URA_index  => :URA,
    :dot_i0     => [:IDot, -43, true],
    #:iode       => nil,
    :t_oc       => [:Toc, 4],
    :a_f2       => [:AF2, -55],
    :a_f1       => [:AF1, -43],
    :a_f0       => [:AF0, -31],
    :iodc       => :IODC,
    :c_rs       => [:Crs, -5],
    :delta_n    => [:DeltaN, -43, true],
    :M0         => [:M0, -31, true],
    :c_uc       => [:Cuc, -29],
    :e          => [:E, -33],
    :c_us       => [:Cus, -29],
    :sqrt_A     => [:APowerHalf, -19],
    :t_oe       => [:Toe, 4],
    :c_ic       => [:Cic, -29],
    :Omega0     => [:OmegaA0, -31, true],
    :c_is       => [:Cis, -29],
    :i0         => [:I0, -31, true],
    :c_rc       => [:Crc, -5],
    :omega      => [:W, -31, true],
    :dot_Omega0 => [:OmegaADot, -43, true],
    :t_GD       => [:Tgd, -31],
    :SV_health  => :SVhealth,
  }.collect{|dst_k, (src_k, sf_pow2, sc2rad)|
    sf_pow2 ||= 0
    sf = sf_pow2 < 0 ? Rational(1, 1 << -sf_pow2) : (1 << sf_pow2)
    sf = sf.to_f * GPS::GPS_SC2RAD if sc2rad
    ["#{dst_k}=".to_sym, ["ephem#{src_k}".to_sym, sf]]
  }.flatten(1))]
=begin
:ephemCodeOnL2 
:ephemL2Pflag
:ephemAODA
=end

  ALM_KEY_TBL_RRLP = Hash[*({
    :e => [:almanacE, -21],
    :i0 => [:almanacKsii, -19, true],
    :dot_Omega0 => [:almanacOmegaDot, -38, true],
    :SV_health => :almanacSVhealth,
    :sqrt_A => [:almanacAPowerHalf, -11],
    :Omega0 => [:almanacOmega0, -23, true],
    :omega => [:almanacW, -23, true],
    :M0 => [:almanacM0, -23, true],
    :a_f0 => [:almanacAF0, -20], 
    :a_f1 => [:almanacAF1, -38],
  }.collect{|dst_k, (src_k, sf_pow2, sc2rad)|
    sf_pow2 ||= 0
    sf = sf_pow2 < 0 ? Rational(1, 1 << -sf_pow2) : (1 << sf_pow2)
    sf = sf.to_f * GPS::GPS_SC2RAD if sc2rad
    ["#{dst_k}=".to_sym, [src_k, sf]]
  }.flatten(1))]

  def attach_rrlp(msg)
    t_gps = proc{
      week_rem, sec008 = [:gpsWeek, :gpsTOW23b].collect{|k| msg[:referenceTime][:gpsTime][k]}
      GPS::Time::new(
          SUPL_Client::correct_gps_week(week_rem, GPS::Time::now),
          Rational(sec008 * 8, 100).to_f)
    }.call
    msg.define_singleton_method(:ref_time){t_gps}
    msg.define_singleton_method(:iono_utc){
      params = GPS::Ionospheric_UTC_Parameters::new
      iono = self[:ionosphericModel]
      a, b = (0..3).collect{|i|
        [iono["alfa#{i}".to_sym], iono["beta#{i}".to_sym]]
      }.transpose
      params.alpha = a.zip([-30, -27, -24, -24]).collect{|v, pow2|
        (v * Rational(1, 1 << -pow2)).to_f
      }
      params.beta = b.zip([11, 14, 16, 16]).collect{|v, pow2|
        v * (1 << pow2)
      }
      utc = self[:utcModel]
      [:A1, :A0, [:t_ot, :Tot], [:WN_t, :WNt], [:delta_t_LS, :DeltaTls],
          [:WN_LSF, :WNlsf], :DN, [:delta_t_LSF, :DeltaTlsf]].each{|k_dst, k_src|
        params.send("#{k_dst}=".to_sym, utc["utc#{k_src || k_dst}".to_sym])
      }
      {:A1 => -50, :A0 => -30, :t_ot => 12}.each{|k, pow2|
        params.send("#{k}=".to_sym,
            params.send(k) * (pow2 < 0 ? Rational(1, 1 << -pow2) : (1 << pow2)))
      }
      params.WN_t = SUPL_Client::correct_gps_week(params.WN_t, t_gps, 256)
      params.WN_LSF = SUPL_Client::correct_gps_week(params.WN_LSF, t_gps, 256)
      params
    }
    msg.define_singleton_method(:ephemeris){
      next [] unless (model = self[:navigationModel])
      model[:navModelList].collect{|sat|
        eph = GPS::Ephemeris::new
        eph.svid = sat[:satelliteID] + 1
        eph_src = sat[:satStatus][:newSatelliteAndModelUC]
        EPH_KEY_TBL_RRLP.each{|dst_k, (src_k, sf)|
          v = sf * eph_src[src_k]
          eph.send(dst_k, v.kind_of?(Rational) ? v.to_f : v)
        }
        eph.WN = t_gps.week
        delta_sec = t_gps.seconds - eph.t_oe
        if delta_sec > GPS::Time::Seconds_week / 2 then
          eph.WN += 1
        elsif delta_sec < -GPS::Time::Seconds_week / 2 then
          eph.WN -= 1
        end
        eph.iode = eph.iodc & 0xFF
        eph.fit_interval = (eph_src[:ephemFitFlag] != 0)
        eph
      }
    }
    msg.define_singleton_method(:almanac){
      next [] unless (model = self[:almanac])
      week = self[:almanac][:alamanacWNa]
      week += (t_gps.week >> 8) << 8
      model[:almanacList].collect{|sat|
        eph = GPS::Ephemeris::new
        eph.svid = sat[:satelliteID] + 1
        ALM_KEY_TBL_RRLP.each{|dst_k, (src_k, sf)|
          v = sf * sat[src_k]
          eph.send(dst_k, v.kind_of?(Rational) ? v.to_f : v)
        }
        eph.i0 = GPS::GPS_SC2RAD * 0.3 + eph.i0
        eph.WN = week
        eph.t_oc = eph.t_oe = sat[:alamanacToa] << 12
        [:iodc, :t_GD, :a_f2, :iode, :c_rs, :delta_n,
            :c_uc, :c_us, :c_ic, :c_is, :c_rc, :dot_i0, :iode_subframe3].each{|k|
          eph.send("#{k}=", 0)
        }
        eph.URA_index = -1
        #eph.fit_interval
        eph
      }
    }
    :alamanacToa # typo in TS
    msg
  end

  EPH_KEY_TBL_LPP = Hash[*({
    :URA_index  => :URA,
    :dot_i0     => [:IDot, -43, true],
    #:iode       => nil,
    :t_oc       => [:Toc, 4],
    :a_f2       => [:af2, -55],
    :a_f1       => [:af1, -43],
    :a_f0       => [:af0, -31],
    #:iodc       => :IODC,
    :c_rs       => [:Crs, -5],
    :delta_n    => [:DeltaN, -43, true],
    :M0         => [:M0, -31, true],
    :c_uc       => [:Cuc, -29],
    :e          => [:E, -33],
    :c_us       => [:Cus, -29],
    :sqrt_A     => [:APowerHalf, -19],
    :t_oe       => [:Toe, 4],
    :c_ic       => [:Cic, -29],
    :Omega0     => [:OmegaA0, -31, true],
    :c_is       => [:Cis, -29],
    :i0         => [:I0, -31, true],
    :c_rc       => [:Crc, -5],
    :omega      => [:Omega, -31, true],
    :dot_Omega0 => [:OmegaADot, -43, true],
    :t_GD       => [:Tgd, -31],
  }.collect{|dst_k, (src_k, sf_pow2, sc2rad)|
    sf_pow2 ||= 0
    sf = sf_pow2 < 0 ? Rational(1, 1 << -sf_pow2) : (1 << sf_pow2)
    sf = sf.to_f * GPS::GPS_SC2RAD if sc2rad
    ["#{dst_k}=".to_sym, ["nav#{src_k}".to_sym, sf]]
  }.flatten(1))]
=begin
:ephemCodeOnL2 
:ephemL2Pflag
:ephemAODA
=end
  
  EPH_KEY_TBL_LPP_GLO = Hash[*({
    :xn => [:X, Rational(1000, 1 << 11)], :xn_dot => [:Xdot, Rational(1000, 1 << 20)], :xn_ddot => [:Xdotdot, Rational(1000, 1 << 30)], 
    :yn => [:Y, Rational(1000, 1 << 11)], :yn_dot => [:Ydot, Rational(1000, 1 << 20)], :yn_ddot => [:Ydotdot, Rational(1000, 1 << 30)],
    :zn => [:Z, Rational(1000, 1 << 11)], :zn_dot => [:Zdot, Rational(1000, 1 << 20)], :zn_ddot => [:Zdotdot, Rational(1000, 1 << 30)],
    :tau_n => [:Tau, Rational(1, 1 << 30)],
    :gamma_n => [:Gamma, Rational(1, 1 << 40)],
    :M => :M, :P1_index => :P1, :P2 => :P2, :E_n => :En,
  }.collect{|dst_k, (src_k, sf)|
    ["#{dst_k}=".to_sym, ["glo#{src_k}".to_sym, sf || 1]]
  }.flatten(1))]
=begin
:has_string=, :raw=, :t_k=,
:N_T=, :p=, :delta_tau_n=, :P4=,
:tau_GPS=, :tau_c=, :day_of_year=, :year=, :n=, :freq_ch=
=end

  ALM_KEY_TBL_LPP = Hash[*({
    :e => [:E, -21],
    :i0 => [:DeltaI, -19, true],
    :dot_Omega0 => [:OMEGADOT, -38, true],
    :SV_health => :SVHealth,
    :sqrt_A => [:SqrtA, -11],
    :Omega0 => [:OMEGAo, -23, true],
    :omega => [:Omega, -23, true],
    :M0 => [:Mo, -23, true],
    :a_f0 => [:af0, -20], 
    :a_f1 => [:af1, -38],
  }.collect{|dst_k, (src_k, sf_pow2, sc2rad)|
    sf_pow2 ||= 0
    sf = sf_pow2 < 0 ? Rational(1, 1 << -sf_pow2) : (1 << sf_pow2)
    sf = sf.to_f * GPS::GPS_SC2RAD if sc2rad
    ["#{dst_k}=".to_sym,
        [(src_k.kind_of?(Symbol) ? "navAlm#{src_k}" : src_k).to_sym, sf]]
  }.flatten(1))]
  
  def attach_lpp(msg)
    t_gps = proc{|data|
      raise unless data[:"gnss-TimeID"][:"gnss-id"] == :gps
      dayn, tod, msec = [:"gnss-DayNumber", :"gnss-TimeOfDay", :"gnss-TimeOfDayFrac-msec"].collect{|k|
        data[k]
      }
      week, dow = dayn.divmod(7)
      GPS::Time::new(week, dow * 24 * 3600 + tod + Rational(msec, 1000).to_f)
    }.call(msg[:c1][:provideAssistanceData][:criticalExtensions][:c1] \
        [:"provideAssistanceData-r9"][:"a-gnss-ProvideAssistanceData"] \
        [:"gnss-CommonAssistData"][:"gnss-ReferenceTime"][:"gnss-SystemTime"])
    msg.define_singleton_method(:ref_time){t_gps}
    iono_utc = proc{
      params = GPS::Ionospheric_UTC_Parameters::new
      proc{|data|
        a, b = (0..3).collect{|i|
          [data["alfa#{i}".to_sym], data["beta#{i}".to_sym]]
        }.transpose
        params.alpha = a.zip([-30, -27, -24, -24]).collect{|v, pow2|
          (v * Rational(1, 1 << -pow2)).to_f
        }
        params.beta = b.zip([11, 14, 16, 16]).collect{|v, pow2|
          v * (1 << pow2)
        }
      }.call(msg[:c1][:provideAssistanceData][:criticalExtensions][:c1] \
          [:"provideAssistanceData-r9"][:"a-gnss-ProvideAssistanceData"] \
          [:"gnss-CommonAssistData"][:"gnss-IonosphericModel"][:klobucharModel])
      proc{|data|
        [[:A1], [:A0], [:t_ot, :Tot],
            [:WN_t, :WNt], [:delta_t_LS, :DeltaTlsf],
            [:WN_LSF, :WNlsf], [:DN], [:delta_t_LSF, :DeltaTlsf]].each{|k_dst, k_src|
          params.send("#{k_dst}=".to_sym, data["gnss-Utc-#{k_src || k_dst}".to_sym])
        }
      }.call(msg[:c1][:provideAssistanceData][:criticalExtensions][:c1] \
          [:"provideAssistanceData-r9"][:"a-gnss-ProvideAssistanceData"] \
          [:"gnss-GenericAssistData"].select{|v| v[:"gnss-ID"][:"gnss-id"] == :gps}[0] \
          [:"gnss-UTC-Model"][:utcModel1])
      {:A1 => -50, :A0 => -30, :t_ot => 12}.each{|k, pow2|
        params.send("#{k}=".to_sym,
            params.send(k) * (pow2 < 0 ? Rational(1, 1 << -pow2) : (1 << pow2)))
      }
      params.WN_t = SUPL_Client::correct_gps_week(params.WN_t, t_gps, 256)
      params.WN_LSF = SUPL_Client::correct_gps_week(params.WN_LSF, t_gps, 256)
      params
    }.call
    leap_seconds = iono_utc.delta_t_LS rescue t_gps.leap_seconds
    msg.define_singleton_method(:iono_utc){iono_utc}
    extract_gps_ephemeris = proc{|model, sys|
      offset = {:gps => 1, :qzss => 193}[sys]
      model[:"gnss-SatelliteList"].collect{|v|
        eph = GPS::Ephemeris::new
        eph.svid = v[:svID][:"satellite-id"] + offset
        eph_src = v[:"gnss-ClockModel"][:"nav-ClockModel"].merge(v[:"gnss-OrbitModel"][:"nav-KeplerianSet"])
        EPH_KEY_TBL_LPP.each{|dst_k, (src_k, sf)|
          v2 = sf * eph_src[src_k]
          eph.send(dst_k, v2.kind_of?(Rational) ? v2.to_f : v2)
        }
        eph.iodc = Integer(v[:iod].join, 2)
        eph.iode = (eph.iodc & 0xFF)
        eph.SV_health = Integer(v[:svHealth][0..5].join, 2)
        eph.WN = t_gps.week
        delta_sec = t_gps.seconds - eph.t_oe
        if delta_sec > GPS::Time::Seconds_week / 2 then
          eph.WN += 1
        elsif delta_sec < -GPS::Time::Seconds_week / 2 then
          eph.WN -= 1
        end
        eph.fit_interval = (eph_src[:navFitFlag] != 0)
        eph
      }
    }
    msg.define_singleton_method(:ephemeris){
      assist_data = self[:c1][:provideAssistanceData][:criticalExtensions][:c1] \
          [:"provideAssistanceData-r9"][:"a-gnss-ProvideAssistanceData"] \
          [:"gnss-GenericAssistData"]
      res = [:gps, :qzss].collect{|k|
        model = assist_data.find{|v| v[:"gnss-ID"][:"gnss-id"] == k}[:"gnss-NavigationModel"] rescue nil
        next [] unless model
        extract_gps_ephemeris.call(model, k)
      }.flatten(1)
      proc{|assist_data_glo|
        next unless assist_data_glo
        next unless nav_model = assist_data_glo[:"gnss-NavigationModel"]
        utc_params_glo = {
          :tau_c= => [:tauC, Rational(1, 1 << 31)],
        }.collect{|dst_k, (src_k, sf)|
          [dst_k, sf * assist_data_glo[:"gnss-UTC-Model"][:utcModel3][src_k]]
        }
        res += nav_model[:"gnss-SatelliteList"].collect{|sat|
          eph = GPS::Ephemeris_GLONASS::new
          eph.svid = sat[:svID][:"satellite-id"] + 1
          eph_src = sat[:"gnss-ClockModel"][:"glonass-ClockModel"].merge(
              sat[:"gnss-OrbitModel"][:"glonass-ECEF"])
          (EPH_KEY_TBL_LPP_GLO.collect{|dst_k, (src_k, sf)|
            v = eph_src[src_k]
            [dst_k, sf.send(sf.kind_of?(Proc) ? :call : :*, case v
                when Array; Integer(v.join, 2)
                when true; 1
                when false; 0
                else; v
                end)]
          } + utc_params_glo).each{|dst_k, v|
            eph.send(dst_k, v.kind_of?(Rational) ? v.to_f : v)
          }
          eph.B_n = sat[:svHealth][0]
          eph.F_T_index = Integer(sat[:svHealth][1..4].join, 2)
          eph.t_b = Integer(sat[:iod][4..-1].join, 2) * 15 * 60
          eph.set_date((t_gps + 3 * 60 * 60).c_tm(leap_seconds)) # UTC -> Moscow time
          eph.N_T = eph.NA
          eph.rehash(leap_seconds)
          eph
        }
      }.call(assist_data.find{|v| v[:"gnss-ID"][:"gnss-id"] == :glonass})
      res
    }
    extract_gps_almanac = proc{|alm, sys|
      next [] unless alm
      offset = {:gps => 1, :qzss => 193}[sys]
      week = alm[:weekNumber] # optional but required for non-GLONASS
      week += (t_gps.week >> 8) << 8
      t_oa = alm[:toa] << 12 # optional but required for non-GLONASS
      alm[:"gnss-AlmanacList"].collect{|v|
        next unless v = v[:"keplerianNAV-Almanac"]
        eph = GPS::Ephemeris::new
        eph.svid = v[:svID][:"satellite-id"] + offset
        ALM_KEY_TBL_LPP.each{|dst_k, (src_k, sf)|
          v2 = sf * v[src_k]
          eph.send(dst_k, v2.kind_of?(Rational) ? v2.to_f : v2)
        }
        eph.i0 = GPS::GPS_SC2RAD * 0.3 + eph.i0
        eph.WN = week
        eph.t_oc = eph.t_oe = t_oa
        [:iodc, :t_GD, :a_f2, :iode, :c_rs, :delta_n,
            :c_uc, :c_us, :c_ic, :c_is, :c_rc, :dot_i0, :iode_subframe3].each{|k|
          eph.send("#{k}=", 0)
        }
        eph.URA_index = -1
        #eph.fit_interval
        eph
      }.compact
    }
    msg.define_singleton_method(:almanac){
      assist_data = self[:c1][:provideAssistanceData][:criticalExtensions][:c1] \
          [:"provideAssistanceData-r9"][:"a-gnss-ProvideAssistanceData"] \
          [:"gnss-GenericAssistData"]
      [:gps, :qzss].collect{|k|
        model = assist_data.find{|v| v[:"gnss-ID"][:"gnss-id"] == k}[:"gnss-Almanac"] rescue nil
        next [] unless model
        extract_gps_almanac.call(model, k)
      }.flatten(1)
    }
    msg
  end
end
end

require 'open-uri'

OpenURI.class_eval{
  def OpenURI.open_supl(buf, target, proxy, options) # :nodoc:
    options[:port] = target.port
    URI.decode_www_form(target.query || "").each{|k, v|
      case k = k.to_sym
      when :protocol, :req_data
        (options[k] ||= []) << v.to_sym
      end
    }
    buf.instance_eval{
      @io = GPS_PVT::SUPL_Client::new(target.host, options)
      @io.define_singleton_method(:read){
        require 'json'
        JSON::pretty_generate(self.get_assisted_data)
      }
      @io.define_singleton_method(:closed?){true} # For open-uri auto close
    }
  end
}
module URI
  class Supl < Generic
    DEFAULT_PORT = 7275
    def buffer_open(buf, proxy, options)
      OpenURI.open_supl(buf, self, proxy, options)
    end
    include OpenURI::OpenRead
  end
  if respond_to?(:register_scheme) then
    register_scheme('SUPL', Supl)
  else
    @@schemes['SUPL'] = Supl
  end
end
