-- /api/v1/measurement/1000000/result/
-- /api/v1/measurement/1000000/
-- /api/v1/measurement/
-- /api/v1/status-checks//1000000/
-- /api/v1/measurement-latest/1000000/
-- /api/v1/probe/
-- /api/v1/probe/123/
-- /dnsmon/group/root
-- /dnsmon/api/probes
-- /dnsmon/api/servers
-- ?format=json&start=1419562800&stop=1419563400

local l = require "lpeg"
l.locale(l)
local clf = require "common_log_format"

local log_format    = read_config("log_format")
local msg_type      = read_config("type")
local uat           = read_config("user_agent_transform")
local uak           = read_config("user_agent_keep")
local uac           = read_config("user_agent_conditional")
local payload_keep  = read_config("payload_keep")

local sp = l.space^0
local http_sep = l.P"/"^0

local api_name = (l.alpha + l.P"-")^1
local api_version = (l.alpha + l.digit)^1
local api_resource = l.digit^1
local api_result = l.alpha^1 / "true"

local atlas_grammar = "/api/" * l.Cg(api_version,"api_version") * http_sep
    * l.Cg(api_name, "api_name") * http_sep
    * (l.Cg(api_resource, "api_resource") * http_sep)^0
    * (l.Cg(api_result, "api_result") * http_sep)^0

local dnsmon_group = (l.alpha + l.P".")^1
local dnsmon_group = "/dnsmon/group/" * l.Cg(dnsmon_group^1,"dnsmon_group")
local dnsmon_api = "/dnsmon/api/" * l.Cg(l.alpha^1,"dnsmon_api")

local dnsmon_grammar = dnsmon_api + dnsmon_group

local api_start = l.P"?"
local api_sep = l.P"&"
local api_parameter = l.C((l.alpha + l.digit + l.S"%_-,.")^0)
local api_kv = l.Cg(api_parameter * "=" * api_parameter) * api_sep^-1

local api_grammar = l.Ct(atlas_grammar + dnsmon_grammar)
local api_param_grammar = l.Cf(l.Ct(api_start) * api_kv^0, rawset)
local log_grammar = clf.build_apache_grammar(log_format)

local msg = {
    Timestamp   = nil,
    Type        = msg_type,
    Payload     = nil,
    Fields      = nil
}

function process_message ()
    local log = read_message("Payload")
    local fields = log_grammar:match(log)
    if not fields then return -1 end

    msg.Timestamp = fields.time
    fields.time = nil

    if payload_keep then
        msg.Payload = log
    end

    if fields.http_user_agent and uat then
        fields.user_agent_browser,
        fields.user_agent_version,
        fields.user_agent_os = clf.normalize_user_agent(fields.http_user_agent)
        if not ((uac and not fields.user_agent_browser) or uak) then
            fields.http_user_agent = nil
        end
    end

    if fields.uri then
        local m = api_grammar:match(fields.uri)
        if m then
            for k,v in pairs(m) do fields[k] = v end
        end
    end
    m = nil
    -- dont obsess with logging, match api_param_grammar only in dnsmon/atlas API query_strings
    -- FIXME
    if fields.api_version or fields.dnsmon_api or fields.dnsmon_group then
        m = api_param_grammar:match(fields.query_string)
    end
    if m then
        for k,v in pairs(m) do fields["api_" .. k] = v end
    end
    msg.Fields = fields
    inject_message(msg)
    return 0
end
