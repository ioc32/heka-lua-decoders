local l = require "lpeg"
l.locale(l)
local dt = require "date_time"

local sp = l.space^1
local sep = l.S":-"
local newline = l.P"\n"
local date = l.Ct(dt.date_fullyear * sep * dt.date_month * sep * dt.date_mday * sp * dt.rfc3339_partial_time)
local data = (l.P(1) - newline)^0
local action = l.P"Install" / "install"
    + l.P"Purge" / "purge"
    + l.P"Remove" / "remove"
    + l.P"Reinstall" / "reinstall"
    + l.P"Upgrade" / "upgrade"

local start_time = l.P"Start-Date: " * l.Cg(date / dt.time_to_ns, "start_time")
local end_time = l.P"End-Date: " * l.Cg(date / dt.time_to_ns, "end_time")
local command = l.P"Commandline: " * l.Cg(data, "command")
local transaction = l.Cg(action, "action") * sep * sp * l.Cg(data, "transaction_log")
local err = l.P"Error" *sep *sp * l.Cg(data, "error")

local grammar = l.Ct(start_time * newline
    * (command * newline)^-1
    * (transaction * newline)^0
    * (err * newline)^-1
    * (end_time)^-1)

local msg_type = read_config("type") or "apt-history-log"
local payload_keep = read_config("payload_keep")

local msg = {
    Timestamp = nil,
    Type = msg_type,
    Payload = nil,
    Fields = nil
}

function process_message()
    local log = read_message("Payload")
    local fields = grammar:match(log)
    if not fields then return -1 end

    msg.Timestamp = fields.time
    fields.time = nil

   if payload_keep then
       msg.Payload = log
   end

   msg.Fields = fields
   if not pcall(inject_message, msg) then return -1 end
   return 0
end
