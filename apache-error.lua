-- [Fri Dec 19 03:33:03.831381 2014] [ssl:warn] [pid 21728] AH01909: RSA certificate configured for ui1.example.net:443 does NOT include an ID which matches the server name
-- [Fri Dec 19 03:33:28.709266 2014] [:error] [pid 19269] [remote 2001:db8::1:232] mod_wsgi (pid=19269): Exception occurred processing WSGI script '/path/django.wsgi'.
-- [Thu Nov 20 04:41:58 2014] [error] [client 127.0.0.1] File does not exist: /var/www/html/@@errordocument, referer: https://example.net/portal_css/resource.search-cachekey-26e2e7db804438d3f5aec0776d05827d.css
-- [Thu Mar 12 20:18:20.120391 2015] [:error] [pid 6782] <tr><th><label for="id_nfyemail">Notification email address:</label></th><td><input class="required" id="id_nfyemail" name="nfyemail" type="text" value="user@example.net" /></td></tr>

local l = require "lpeg"
l.locale(l)
local dt = require "date_time"
local ip = require "ip_address"

local msg_type      = read_config("type")
local payload_keep  = read_config("payload_keep")

local sp = l.space
local sep = l.P":"

local apache_error_component = (l.Cg((l.alpha + l.S"-_")^1, "error_component"))
local apache_error_levels = l.Cg((
    l.P"debug"
    + l.P"info"
    + l.P"notice"
    + l.P"warn"
    + l.P"error"
    + l.P"crit"
    + l.P"alert"
    + l.P"emerg")
    , "error_level")
local ip_addr = ip.v4 + ip.v6
local ip_port = l.Cg(l.digit^1, "remote_port")

local apache_error = "[" * (sep^-1 * apache_error_levels + apache_error_component * sep * apache_error_levels) * "]"
local apache_pid = "[pid " * l.Cg(l.digit^1 / tonumber, "Pid") * "]"
local apache_remote = "[" * (l.P"remote" + l.P"client") * sp * l.Cg(ip_addr, "remote_addr") * (sep * ip_port)^-1 * "]"
local apache_error_msg = l.Cg(l.P(1)^0, "error_msg")

local date_wday = l.P"Mon" + "Tue" + "Wed" + "Thu" + "Fri" + "Sat" + "Sun"
local ts = l.Ct("[" * date_wday * sp * dt.date_mabbr * sp * dt.date_mday * sp * dt.rfc3339_partial_time * sp * dt.date_fullyear * "]")

local apache_error_grammar = l.Ct(l.Cg(ts / dt.time_to_ns, "time")
    * sp^1 * apache_error
    * (sp * apache_pid)^-1
    * (sp * apache_remote)^-1
    * sp * apache_error_msg)

local msg = {
    Timestamp   = nil,
    Type        = msg_type,
    Payload     = nil,
    Fields      = nil
}

function process_message ()
    local log = read_message("Payload")
    local fields = apache_error_grammar:match(log)
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
