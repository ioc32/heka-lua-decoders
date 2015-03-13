-- EXTERNAL COMMAND: DEL_DOWNTIME_BY_HOST_NAME;nikblade-2-16-drac
-- EXTERNAL COMMAND: SCHEDULE_HOST_SVC_DOWNTIME;ws-www-pre-www;1415616253;1415623453;1;0;7200;it;growing /export. emil.
-- EXTERNAL COMMAND: DEL_HOST_DOWNTIME;27714

local l = require "lpeg"
l.locale(l)
local dt = require "date_time"
local tonumber = tonumber

local msg_type      = read_config("type") or "icinga-log"
local payload_keep  = read_config("payload_keep")

local sp = l.space^1
local sep = l.S":;"

local entity = l.Cg((l.alnum + l.S"-._/")^1, "entity")
local contact = l.Cg((l.alnum + l.P"-")^1, "contact")
local notification_svc = l.Cg((l.alnum + l.S"-_")^1, "notification_service")

local svc = l.Cg((l.alnum + l.S"-_/.:" + sp)^1, "service")
local svc_state = l.Cg(
    l.P"OK"
    + l.P"WARNING"
    + l.P"CRITICAL"
    + l.P"UNKNOWN"
    + l.P"ACKNOWLEDGEMENT (WARNING)" / "ACKNOWLEDGEMENT WARNING"
    + l.P"ACKNOWLEDGEMENT (CRITICAL)" / "ACKNOWLEDGEMENT CRITICAL"
    + l.P"ACKNOWLEDGEMENT (UNKNOWN)" / "ACKNOWLEDGEMENT UNKNOWN"
    , "state"
)
local host_state = l.Cg(
    l.P"UP"
    + l.P"DOWN"
    + l.P"UNREACHABLE"
    , "state"
)
local downtime_state = l.Cg(
    l.P"STARTED"
    + l.P"STOPPED"
    + l.P"CANCELLED"
    , "downtime_state"
)
local state_type = l.Cg(l.P"HARD" + l.P"SOFT", "state_type")
local current_check = l.Cg(l.digit^1 / tonumber, "current_check")
local data = l.Cg(l.P(1)^0, "output")

local ts = l.P"[" * l.Cg(l.digit^1 / tonumber, "time") * l.P"]"

local header = l.Cg(
    l.P"CURRENT SERVICE STATE"
    + l.P"CURRENT HOST STATE"
    + l.P"SERVICE ALERT"
    + l.P"HOST ALERT"
    + l.P"SERVICE NOTIFICATION"
    + l.P"HOST NOTIFICATION"
    + l.P"SERVICE FLAPPING ALERT"
    + l.P"HOST FLAPPING ALERT"
    + l.P"PASSIVE SERVICE CHECK"
    + l.P"PASSIVE HOST CHECK"
    + l.P"EXTERNAL COMMAND"
    + l.P"SERVICE DOWNTIME ALERT"
    + l.P"HOST DOWNTIME ALERT"
    + l.P"SERVICE DOWNTIME ALERT"
    + l.P"Warning" / "ICINGA WARNING"
    + l.P"Error" / "ICINGA WARNING"
    + l.P"LOG ROTATION"
    + l.P"LOG VERSION"
    , "log_type")

local current_svc_state =
    entity * sep
    * svc * sep
    * svc_state * sep
    * state_type * sep
    * current_check * sep
    * data

local current_host_state =
    entity * sep
    * host_state * sep
    * state_type * sep
    * current_check * sep
    * data

local svc_alert =
    entity * sep
    * svc * sep
    * svc_state * sep
    * state_type * sep
    * current_check * sep
    * data

local host_alert =
    entity * sep
    * host_state * sep
    * state_type * sep
    * data

local svc_notification =
    contact * sep
    * entity * sep
    * svc * sep
    * svc_state * sep
    * notification_svc * sep
    * data

local host_notification =
    contact * sep
    * entity * sep
    * host_state * sep
    * notification_svc * sep
    * data

local icinga_command = l.Cg((l.R"AZ" + l.S"_-")^1, "command")
local command =
    icinga_command * sep
    * data

local svc_downtime =
    entity * sep
    * svc * sep
    * downtime_state * sep
    * data

local host_downtime =
    entity * sep
    * downtime_state * sep
    * data

local current_state = current_svc_state + current_host_state
local alert = svc_alert + host_alert
local notification = svc_notification + host_notification
local downtime = svc_downtime + host_downtime

local payload = current_state + alert + notification + command + downtime + data

local icinga_grammar = l.Ct(ts * sp * (header * sep * sp)^-1 * payload )

local msg = {
    Timestamp   = nil,
    Type        = msg_type,
    Payload     = nil,
    Fields      = nil
}

function process_message ()
    local log = read_message("Payload")
    local fields = icinga_grammar:match(log)
    if not fields then return -1 end

    msg.Timestamp = fields.time * 1e9
    fields.time = nil

    if payload_keep then
        msg.Payload = log
    end

    msg.Fields = fields
    if not pcall(inject_message, msg) then return -1 end
    return 0
end
