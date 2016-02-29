--[[

Can be deployed together with ProcessInput:

[hdp-zk-mntr]
type = "ProcessInput"
ticker_interval = 60
splitter = "NullSplitter"
decoder = "hdp-zk-mntr-decoder"
stdout = true
stderr = true

[hdp-zk-mntr.command.0]
bin = "/bin/echo"
args = ["mntr"]

[hdp-zk-mntr.command.1]
bin = "/usr/bin/nc"
args = ["localhost", "2181"]

[hdp-zk-mntr-decoder]
type = "SandboxDecoder"
filename = "/usr/share/heka/lua_decoders/zk_mntr.lua"

Input sample:

zk_version      3.4.5-cdh5.4.7--1, built on 09/17/2015 09:14 GMT
zk_avg_latency  0
zk_max_latency  161
zk_min_latency  0
zk_packets_received     79461773
zk_packets_sent 79520073
zk_num_alive_connections        86
zk_outstanding_requests 0
zk_server_state leader
zk_znode_count  21470
zk_watch_count  2024
zk_ephemerals_count     131
zk_approximate_data_size        384036623
zk_open_file_descriptor_count   123
zk_max_file_descriptor_count    4096
zk_followers    4
zk_synced_followers     4
zk_pending_syncs        0
]]--

local l = require 'lpeg'
l.locale(l)

sp = l.space^1
sep = l.P"\n" + l.P"\n\r" + l.P"\r\n" + l.P"\r"

local msg_type      = read_config("type") or "zk-mntr"
local payload_keep  = read_config("payload_keep") or false
local cluster_name = read_config("cluster_name")

local msg = {
Type        = msg_type,
Payload     = nil,
Fields      = nil
}

local zk_mntr_grammar = l.Ct(
  l.P"zk_version" * sp * l.Cg((1 - sep)^0, "zk_version") * sep
* l.P"zk_avg_latency" * sp * l.Cg(l.digit^1 / tonumber,"zk_avg_latency") * sep
* l.P"zk_max_latency" * sp * l.Cg(l.digit^1 / tonumber,"zk_max_latency") * sep
* l.P"zk_min_latency" * sp * l.Cg(l.digit^1 / tonumber,"zk_min_latency") * sep
* l.P"zk_packets_received" * sp * l.Cg(l.digit^1 / tonumber,"zk_packets_received") * sep
* l.P"zk_packets_sent" * sp * l.Cg(l.digit^1 / tonumber,"zk_packets_sent") * sep
* l.P"zk_num_alive_connections" * sp * l.Cg(l.digit^1 / tonumber,"zk_num_alive_connections") * sep
* l.P"zk_outstanding_requests" * sp * l.Cg(l.digit^1 / tonumber,"zk_outstanding_requests") * sep
* l.P"zk_server_state" * sp * l.Cg(l.alpha^1,"zk_server_state") * sep
* l.P"zk_znode_count" * sp * l.Cg(l.digit^1 / tonumber,"zk_znode_count") * sep
* l.P"zk_watch_count" * sp * l.Cg(l.digit^1 / tonumber,"zk_watch_count") * sep
* l.P"zk_ephemerals_count" * sp * l.Cg(l.digit^1 / tonumber,"zk_ephemerals_count") * sep
* l.P"zk_approximate_data_size" * sp * l.Cg(l.digit^1 / tonumber,"zk_approximate_data_size") * sep
* l.P"zk_open_file_descriptor_count" * sp * l.Cg(l.digit^1 / tonumber,"zk_open_file_descriptor_count") * sep
* l.P"zk_max_file_descriptor_count" * sp * l.Cg(l.digit^1 / tonumber,"zk_max_file_descriptor_count") * sep
* (l.P"zk_followers" * sp * l.Cg(l.digit^1 / tonumber,"zk_followers") * sep)^-1
* (l.P"zk_synced_followers" * sp * l.Cg(l.digit^1 / tonumber,"zk_synced_followers") * sep)^-1
* (l.P"zk_pending_syncs" * sp * l.Cg(l.digit^1 / tonumber,"zk_pending_syncs"))^-1
)

function process_message ()
    local log = read_message("Payload")
    local fields = zk_mntr_grammar:match(log)
    if not fields then return -1 end

    if payload_keep then
        msg.Payload = log
    end
    fields.cluster= cluster_name
    msg.Fields = fields
    if not pcall(inject_message, msg) then return -1 end
    return 0
end
