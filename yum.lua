local l = require "lpeg"
l.locale(l)
local dt = require "date_time"
local tonumber = tonumber

local payload_keep = read_config("payload_keep")
local match_package = read_config("match_package")

local action = l.Cg(l.P"Installed" / "install"
    + l.P"Updated" / "update"
    + l.P"Erased" / "erase",
    "action")
local sp = l.space^0
local sep = l.S":-."
local epoch = l.Cg(l.Ct(l.Cg(l.digit^1 / tonumber, "value") * l.Cg(l.Cc"count", "representation") * sep), "epoch")
local package = l.Cg(l.P(1)^0, "package")

local ts = l.Cg(dt.rfc3164_timestamp / dt.time_to_ns, "time")

local name = l.Cg((l.alnum + l.P"-")^1, "rpm_name")
local version = l.Cg((l.alnum + l.S"-.+_")^1, "rpm_version")
local arch = l.Cg(l.P"x86_64" + l.P"i386" + l.P"noarch", "rpm_arch")
local dist = l.Cg(l.P"el" * (l.digit * l.P"_" * l.digit + l.digit)^-1
    + l.P"rhel" * l.digit^-1
    + l.P"fc" * l.digit^-1,
    "rpm_dist")

local rpm_grammar = l.Ct(name * sep * version * sep * dist * sep * arch)
local yum_grammar = l.Ct(ts * sp * action * sep
    * sp * epoch^-1 * package)

local msg = {
    Timestamp = nil,
    Type = read_config("type"),
    Payload = nil,
    Fields = nil
}

function process_message()
    local log = read_message("Payload")
    local fields = yum_grammar:match(log)
    if not fields then return -1 end

    msg.Timestamp = fields.time
    fields.time = nil

    if match_package then
        local m = rpm_grammar:match(fields.package)
        if m then
            --fields.package = nil
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
