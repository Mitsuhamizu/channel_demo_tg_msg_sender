require_relative "../libs/initialization.rb"
require_relative "../libs/communication.rb"
require_relative "../libs/chain_monitor.rb"
require "mongo"
require "thor"
require "ckb"
Mongo::Logger.logger.level = Logger::FATAL

def pubkey_to_privkey(pubkey)
  @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
  @db = @client.database
  @coll_sessions = @db[pubkey + "_session_pool"]
  private_key = @coll_sessions.find({ id: 0 }).first[:privkey]
  return private_key
end

def hash_to_info(info_h)
  info_h[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
  return info_h
end

def decoder(data)
  result = CKB::Utils.hex_to_bin(data).unpack("Q<")[0]
  return result.to_i
end

def load_config()
  data_raw = File.read("config.json")
  data_json = JSON.parse(data_raw, symbolize_names: true)
  return data_json[:pubkey], data_json[:channel_id], data_json[:robot_ip], data_json[:robot_port]
end

def get_balance(pubkey)
  @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
  @db = @client.database
  @coll_sessions = @db[pubkey + "_session_pool"]

  balance = {}
  # iterate all record.
  view = @coll_sessions.find { }
  view.each do |doc|
    if doc[:id] != 0
      local_pubkey = doc[:local_pubkey]
      remote_pubkey = doc[:remote_pubkey]
      balance[doc[:id]] = {}
      stx = hash_to_info(JSON.parse(doc[:stx_info], symbolize_names: true))
      for index in (0..stx[:outputs].length - 1)
        output = stx[:outputs][index]
        output_data = stx[:outputs_data][index]
        ckb = output.capacity - output.calculate_min_capacity(output_data)
        udt = decoder(stx[:outputs_data][index])
        if local_pubkey == output.lock.args
          balance[doc[:id]][:local] = { ckb: ckb, udt: udt }
        elsif remote_pubkey == output.lock.args
          balance[doc[:id]][:remote] = { ckb: ckb, udt: udt }
        end
      end
      # puts doc[:nounce] - 1
      balance[doc[:id]][:payments] = doc[:nounce] - 1
      balance[doc[:id]][:stage] = doc[:stage]
    end
  end

  return balance
end

def update_config(update_field)
  data_hash = {}
  if File.file?("config.json")
    data_raw = File.read("config.json")
    data_hash = JSON.parse(data_raw, symbolize_names: true)
  end
  data_hash = data_hash.merge(update_field)
  data_json = data_hash.to_json
  file = File.new("config.json", "w")
  file.syswrite(data_json)
end

class GPCCLI < Thor
  desc "init <private-key>", "Init with the private key."
  # --------------init
  def init(private_key)
    if ARGV.length != 2
      puts "The arg number is not right."
      return false
    end
    Init.new(private_key)

    # add the pubkey to the config.json
    data_hash = {}
    if File.file?("config.json")
      data_raw = File.read("config.json")
      data_hash = JSON.parse(data_raw, symbolize_names: true)
    end
    pubkey = { pubkey: CKB::Key.pubkey(private_key) }
    data_hash = data_hash.merge(pubkey)
    data_json = data_hash.to_json
    file = File.new("config.json", "w")
    file.syswrite(data_json)
  end

  # --------------establishment
  desc "send_establishment_request <--funding fundings>",
       "Send the chanenl establishment request."
  option :funding, :required => true, :type => :hash

  def send_establishment_request()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    fundings = options[:funding]

    fundings = fundings.map() { |key, value| [key.to_sym, value] }.to_h

    for asset_type in fundings.keys()
      fundings[asset_type] = asset_type == :ckb ? CKB::Utils.byte_to_shannon(BigDecimal(fundings[asset_type])) : BigDecimal(fundings[asset_type])
      fundings[asset_type] = fundings[asset_type].to_i
    end

    communicator.send_establish_channel(robot_ip, robot_port, fundings)
  end

  # --------------monitor
  desc "monitor [--pubkey public key]", "Monitor the chain."

  option :pubkey

  def monitor()
    pubkey, channel_id, robot_ip, robot_port = load_config()

    if pubkey == nil
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    monitor = Minotor.new(private_key)
    thread_monitor_chain = Thread.start { monitor.monitor_chain() }
    thread_monitor_cell = Thread.start { monitor.monitor_pending_cells() }
    thread_monitor_chain.join
    thread_monitor_cell.join
  end

  # --------------close the channel unilateral
  desc "close_channel [--pubkey pubkey] [--id channel id]", "close the channel with id."
  option :pubkey
  option :id

  def close_channel()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !channel_id
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    monitor = Minotor.new(private_key)

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[pubkey + "_session_pool"]

    doc = @coll_sessions.find({ id: channel_id }).first
    monitor.send_tx(doc, "closing")
  end

  # --------------send the closing request about bilateral closing.
  desc "send_closing_request [--fee fee] ", "The good case, bilateral closing."

  option :fee

  def send_closing_request()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port || !channel_id
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    communicator.send_closing_request(robot_ip robot_port, channel_id, options[:fee].to_i) if options[:fee]
    communicator.send_closing_request(robot_ip, robot_port, channel_id) if !options[:fee]
  end

  # --------------list the channel.
  desc "list_channel [--pubkey public key]", "List channels"

  option :pubkey

  def list_channel()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey
      puts "Please init the config.json."
      return false
    end

    balance = get_balance(pubkey)
    for id in balance.keys()
      puts "channel #{id}, with #{balance[id][:payments]} payments and stage is #{balance[id][:stage]}"
      puts " local's ckb: #{balance[id][:local][:ckb] / 10 ** 8} ckbytes, local's udt #{balance[id][:local][:udt]}."
      puts " remote's ckb: #{balance[id][:remote][:ckb] / 10 ** 8} ckbytes, remote's udt #{balance[id][:remote][:udt]}.\n\n"
    end
  end

  # --------------exchange the ckb and channel.
  desc "make_exchange_ckb_to_udt <--quantity quantity>", "use ckb for udt."
  option :quantity, :required => true

  def make_exchange_ckb_to_udt()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port || !channel_id
      puts "Please init the config.json."
      return false
    end
    private_key = pubkey_to_privkey(pubkey)
    quantity = options[:quantity]
    communicator = Communication.new(private_key)
    communicator.make_exchange(robot_ip, robot_port, channel_id, "ckb2udt", quantity.to_i)
  end

  # --------------exchange the udt and channel.
  desc "make_exchange_ckb_to_udt [--pubkey public key] [--ip ip] [--port port] [--id id] <--quantity quantity>", "use udt for ckb."

  option :quantity, :required => true

  def make_exchange_udt_to_ckb()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port || !channel_id
      puts "Please init the config.json."
      return false
    end
    private_key = pubkey_to_privkey(pubkey)
    quantity = options[:quantity]
    communicator = Communication.new(private_key)
    communicator.make_exchange(robot_ip, robot_port, channel_id, "udt2ckb", quantity.to_i)
  end

  # --------------send_msg by payment channel.
  desc "use_pubkey --pubkey <public key>", "denote the pubkey you want to use."

  option :pubkey, :required => true

  def use_pubkey()
    data_hash = {}
    if File.file?("config.json")
      data_raw = File.read("config.json")
      data_hash = JSON.parse(data_raw, symbolize_names: true)
    end
    pubkey = { pubkey: options[:pubkey] }
    data_hash = data_hash.merge(pubkey)
    data_json = data_hash.to_json
    file = File.new("config.json", "w")
    file.syswrite(data_json)
  end

  desc "use_channel <--id channel id>", "denote the pubkey you want to use."

  option :id, :required => true

  def use_channel()
    data_hash = {}
    if File.file?("config.json")
      data_raw = File.read("config.json")
      data_hash = JSON.parse(data_raw, symbolize_names: true)
    end
    id = { channel_id: options[:id] }
    data_hash = data_hash.merge(id)
    data_json = data_hash.to_json
    file = File.new("config.json", "w")
    file.syswrite(data_json)
  end

  # --------------Inquiry current bid.
  desc "inquiry_bid", "inquiry the left time and price of current bid."

  def inquiry_msg()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    communicator.send_inquiry_bid(robot_ip, robot_port)
  end

  # --------------Inquiry msg.
  desc "inquiry_msg <--text msg_text>", "inquiry the detailed information about this message."

  option :text, :required => true

  def inquiry_msg()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    communicator.send_inquiry_tg_msg(robot_ip, robot_port, options[:text])
  end

  # --------------pin msg.
  desc "pin_msg [--id msg_id] [--duration seconds] [--price price_per_seconds]", "pin a specific msg."

  option :id, :required => true
  option :duration, :required => true
  option :price, :required => true

  def pin_msg()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port || !channel_id
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    balance = get_balance(pubkey)

    udt_required = (options[:duration].to_f * options[:price].to_f).ceil
    udt_actual = balance[channel_id][:local][:udt]

    if udt_actual < udt_required
      puts "you do not have enough udt, please exchange it with ckb first."
    end
    # construct the payment.
    communicator = Communication.new(private_key)
    payment = { udt: udt_required }
    pinned_msg = { text: nil, id: options[:id] }
    communicator.send_payments(robot_ip, robot_port, channel_id, payment, pinned_msg, options[:duration].to_f)
  end

  # --------------send and pin msg.
  desc "send_pinned_msg [--text text] [--duration seconds] [--price price_per_seconds]", "Send and pin the content you want."

  option :text, :required => true
  option :duration, :required => true
  option :price, :required => true

  def send_pinned_msg()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port || !channel_id
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    balance = get_balance(pubkey)

    udt_required = (options[:duration].to_f * options[:price].to_f).ceil
    udt_actual = balance[channel_id][:local][:udt]

    if udt_actual < udt_required
      puts "you do not have enough udt, please exchange it with ckb first."
    end
    # construct the payment.
    communicator = Communication.new(private_key)
    payment = { udt: udt_required }
    pinned_msg = { text: options[:text], id: nil }
    communicator.send_payments(robot_ip, robot_port, channel_id, payment, pinned_msg, options[:duration].to_f)
  end

  # --------------Inquiry msg.
  desc "refund", "Give back the money you didn't use up."

  def refund()
    pubkey, channel_id, robot_ip, robot_port = load_config()
    if !pubkey || !robot_ip || !robot_port
      puts "Please init the config.json."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    communicator.send_refund_request(robot_ip, robot_port, channel_id)
  end

  # --------------Inquiry msg.
  desc "start", "Set up for docker."

  def start()
    pubkey = nil
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @db.collections.each do |collection|
      if collection.name.include? "_session_pool"
        pubkey = collection.name[0..67]
        break
      end
    end
    # find the channel id.
    if pubkey != nil
      update_config({ pubkey: pubkey })
      @coll_sessions = @db[pubkey + "_session_pool"]
      view = @coll_sessions.find { }
      # update channel_id.
      view.each do |doc|
        if doc[:id] != nil
          update_config({ channel_id: doc[:id] })
        end
      end
    end
    # run monitor.

    private_key = pubkey_to_privkey(pubkey)
    monitor = Minotor.new(private_key)
    thread_monitor_chain = Thread.start { monitor.monitor_chain() }
    thread_monitor_cell = Thread.start { monitor.monitor_pending_cells() }
    thread_monitor_chain.join
    thread_monitor_cell.join
  end
end

$VERBOSE = nil
GPCCLI.start(ARGV)
