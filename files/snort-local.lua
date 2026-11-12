-- /etc/snort/local.lua: appended to the generated Snort config
-- (set via: uci set snort.snort.include='/etc/snort/local.lua')

-- Write alerts to syslog as well (LuCI > Status > System Log, logread -e snort:)
alert_syslog = { level = 'info' }

-- Silence noisy rules, globally or per host. Examples:
-- suppress = {
--     { gid = 1, sid = 408 },                                   -- ICMP Echo Reply
--     { gid = 1, sid = 29456, track = 'by_src', ip = '192.168.20.50' },
-- }
