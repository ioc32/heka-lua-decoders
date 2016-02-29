local l = require "lpeg"
l.locale(l)
local dt = require "date_time"

local msg_type      = read_config("type") or "nsd-log"
local payload_keep  = read_config("payload_keep") or true

local sp = l.space
local syslog_severity_text = ((
    (l.P"debug"   + "DEBUG")      / "7"
  + (l.P"info"    + "INFO")       / "6"
  + (l.P"notice"  + "NOTICE")     / "5"
  + (l.P"warning" + "WARNING")    / "4"
  + (l.P"warn"    + "WARN")       / "4"
  + (l.P"error"   + "ERROR")      / "3"
  + (l.P"err"     + "ERR")        / "3"
  + (l.P"crit"    + "CRIT")       / "2"
  + (l.P"alert"   + "ALERT")      / "1"
  + (l.P"emerg"   + "EMERG")      / "0"
  + (l.P"panic"   + "PANIC")      / "0")
  / tonumber)

date_mday_sp = l.Cg(l.digit^1, "day")

local ts = "[" * l.Cg(l.Ct(dt.date_fullyear * "-" * dt.date_month * "-" * date_mday_sp * sp * dt.rfc3339_partial_time) / dt.time_to_ns, "time") * "]"
local nsd_header = "nsd[" * l.Cg((l.digit)^1, "pid") * "]"
local severity = l.Cg(syslog_severity_text, "severity")
local message = l.Cg(l.P(1)^0, "message")
--local message = l.Cg(l.P(-1), "message")

local nsd_grammar = l.Ct(ts * sp * nsd_header * ":" * sp * severity * ":" * sp * message)

local msg = {
    Timestamp   = nil,
    Type        = msg_type,
    Payload     = nil,
    Fields      = nil
}

function process_message ()
    local log = read_message("Payload")
    local fields = nsd_grammar:match(log)
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
