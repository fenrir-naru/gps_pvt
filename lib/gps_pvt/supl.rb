require_relative 'upl/upl'

require 'socket'
require 'openssl'

module GPS_PVT
class SUPL_Client
  include UPL
  
  attr_accessor :debug
  
  def initialize(server_ip, server_port = 7275)
    @server_ip = server_ip
    @server_port = server_port
    @debug = false
  end

  def get_assisted_data
    begin
      @socket = TCPSocket::new(@server_ip, @server_port)
      if @server_port == 7275 then
        @socket = OpenSSL::SSL::SSLSocket::new(@socket)
        @socket.connect
      end
      send_supl_start
      recv_supl_init
      send_supl_pos_init
      recv_supl_pos
    ensure
      @socket.close unless @socket.closed?
    end
  end
  
  private

  def send(cmd)
    msg = encode(cmd)
    p [msg.unpack("C*").collect{|byte| "%02X"%[byte]}.join(' '), decode(msg)] if @debug
    @socket.write(msg)
  end

  def receive
    raw = @socket.read(2)
    raw += @socket.read(raw.unpack("n")[0] - 2)
    res = decode(raw)
    p [raw, res] if @debug
    res
  end

  def send_supl_start
    cmd = generate_skelton(:SUPLSTART)
    cmd[:sessionID][:setSessionID] = {
      :sessionId => 1,
      :setId => {
        #:msisdn => [0xFF, 0xFF, 0x91, 0x94, 0x48, 0x45, 0x83, 0x98],
        :imsi => "440109012345678".scan(/(.)(.?)/).collect{|a, b|
          "0x#{a}#{b == '' ? '0' : b}".to_i(16)
        },
      }
    }
    proc{|cap|
      cap[:posTechnology].keys.each{|k|
        cap[:posTechnology][k] = [:agpsSETBased].include?(k)
      }
      cap[:prefMethod] = :agpsSETBasedPreferred
      cap[:posProtocol].keys.each{|k|
        cap[:posProtocol][k] = [:rrlp].include?(k)
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
  
  
  def recv_supl_init
    data = receive
    @session_id = data[:sessionID]
  end

  def send_supl_pos_init
    cmd = generate_skelton(:SUPLPOSINIT)
    cmd[:sessionID] = @session_id
    proc{|posinit|
      posinit[:sETCapabilities] = @capability
      posinit[:requestedAssistData] = Hash[*([
        :almanacRequested,
        :utcModelRequested,
        :ionosphericModelRequested,
        :dgpsCorrectionsRequested,
        :referenceLocationRequested,
        :referenceTimeRequested,
        :acquisitionAssistanceRequested,
        :realTimeIntegrityRequested,
        :navigationModelRequested
      ].collect{|k|
        [k, [
              :utcModelRequested,
              :ionosphericModelRequested,
              :referenceLocationRequested,
              :referenceTimeRequested,
              :acquisitionAssistanceRequested,
              :realTimeIntegrityRequested,
              :navigationModelRequested,
            ].include?(k)]
      }.flatten(1))]
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
    while true
      data = receive
      rrlp_data = data[:message][:msSUPLPOS][:posPayLoad][:rrlpPayload].decode
      merge.call(
          rrlp_data[:component][:assistanceData][:"gps-AssistData"][:controlHeader],
          res)
      break unless (rrlp_data[:component][:assistanceData][:moreAssDataToBeSent] == :moreMessagesOnTheWay)
      
      # SUPL-POS + RRLP-assistanceDataAck
      cmd = generate_skelton(:SUPLPOS)
      cmd[:sessionID] = @session_id
      cmd[:message][:msSUPLPOS] = {
        :posPayLoad => {:rrlpPayload => {
          :referenceNumber => rrlp_data[:referenceNumber],
          :component => {:assistanceDataAck => nil}
        }}
      }
      send(cmd)
    end
    res
  end
end
end
