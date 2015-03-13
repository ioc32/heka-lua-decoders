local l = require "lpeg"
l.locale(l)
local dt = require "date_time"

local sp = l.space^1
local sep = l.S":-"
local newline = l.P"\n"
local date = l.Ct(dt.date_fullyear * sep * dt.date_month * sep * dt.date_mday * sp * dt.rfc3339_partial_time)
local data = (l.P(1) - newline)^1

local log_start = l.P"Log started: " * l.Cg(date / dt.time_to_ns, "start_time")
local log_end = l.P"Log ended: " * l.Cg(date / dt.time_to_ns, "end_time")
local log_stdout = l.Cg(data, "log_stdout")

local grammar = l.Ct(log_start * newline
    * (log_stdout * newline)^1
    * (log_end)^-1)

local msg_type = read_config("type") or "apt-term-log"
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
