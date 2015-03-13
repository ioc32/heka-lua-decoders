local l = require "lpeg"
l.locale(l)
local dt = require "date_time"

local msg_type      = read_config("type") or "httpd-plone-log"
local payload_keep  = read_config("payload_keep")

local nl = l.P"\n"^-1
local sp = l.space^1

local ts = l.Cg(l.Ct(dt.rfc3339_full_date * "T" * dt.rfc3339_partial_time) / dt.time_to_ns, "time")
local level = l.Cg(
    l.P"DEBUG"
    + l.P"INFO"
    + l.P"NOTICE"
    + l.P"WARNING"
    + l.P"ERROR"
    + l.P"CRIT"
    + l.P"ALERT"
    + l.P"EMERG"
    , "error_level")
local component = l.Cg((l.alnum + l.S"-_.")^1, "component")
local message = l.Cg(l.P(1)^0, "message")

local plone_error_grammar = l.Ct((ts * sp * level * sp * component * sp * message) + message)

local msg = {
    Timestamp   = nil,
    Type        = msg_type,
    Payload     = nil,
    Fields      = nil
}

function process_message ()
    local log = read_message("Payload")
    local fields = plone_error_grammar:match(log)
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
