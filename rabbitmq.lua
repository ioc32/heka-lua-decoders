-- Error in process <0.11849.5> on node 'rabbit@rigel-dev' with exit value: {badarith,[{ssl_session,valid_session,2},{ssl_manager,validate_session,3},{ssl_manager,session_validation,2},{lists,foldl,3},{ets,do_foldl,4},{ets,foldl,3}]}

local l = require "lpeg"
l.locale(l)
local dt = require "date_time"
local ip = require "ip_address"

local msg_type      = read_config("type") or "rabbitmq-log"
local payload_keep  = read_config("payload_keep")
local parse_connection = read_config("parse_connection")

local nl = l.P"\n"
local sp = l.space

local date_mday_sp = l.Cg(l.digit^1, "day")
local ts = l.Cg(l.Ct(date_mday_sp * "-" * dt.date_mabbr * "-" * dt.date_fullyear * "::" * dt.rfc3339_partial_time) / dt.time_to_ns, "time")
local header = "=" * l.Cg(l.alpha^1, "level") * " REPORT==== " * ts * " ==="
local message = l.Cg(l.P(1)^0, "message")

local action = l.Cg(l.P"accepting"
    + l.P"closing"
    + l.P"error on" / "error", "action")
local pid = l.Cg("<" * l.digit^1 * "." * l.digit^1 * "." * l.digit^1 * ">", "erlang_pid")
local node = l.Cg((l.alnum + l.S"@-_.")^1, "erlang_node")

local port = l.digit^1
local ip_addr = ip.v4 + ip.v6
local host = (l.alnum + l.S"-_.")^1
local remote_host = l.Cg(host + ip_addr, "remote_host") * ":" * l.Cg(port, "remote_port")
local local_host = l.Cg(host + ip_addr, "local_host") * ":" * l.Cg(port, "source_port")

local connection = "(" * remote_host * " -> " * local_host * ")"
local connection_error = ":" * nl^-1 * l.Cg(l.P(1)^0, "connection_error")
local connection_soft_error = ", channel " * l.digit^1 * " - " * l.Cg("soft error", "action") * ":" * nl
    * l.Cg(l.P(1)^0, "connection_soft_error")

local connection_grammar = l.Ct(action * " AMQP connection " * pid * (sp * connection)^-1 * connection_error^-1
    + "connection " * pid * connection_soft_error)
local process_error_grammar = l.Ct(l.P"Error in process " * pid * l.P" on node '" * node
    * l.P"' with exit value: " * l.Cg(l.P(1)^0, "process_error"))
local rabbitmq_grammar = l.Ct(header * nl * (process_error_grammar + message))

local msg = {
    Timestamp   = nil,
    Type        = msg_type,
    Payload     = nil,
    Fields      = nil
}

function process_message ()
    local log = read_message("Payload")
    local fields = rabbitmq_grammar:match(log)
    if not fields then return -1 end

    msg.Timestamp = fields.time
    fields.time = nil

    if parse_connection and fields.message then
        local m = connection_grammar:match(fields.message)
        if m then
            for k,v in pairs(m) do fields[k] = v end
        end
    end

    if payload_keep then
        msg.Payload = log
    end

    msg.Fields = fields
    if not pcall(inject_message, msg) then return -1 end
    return 0
end
