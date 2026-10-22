function value = acousticUtcTimestamp()
%ACOUSTICUTCTIMESTAMP The completion time an acoustic run records, in UTC.
value = string(char(datetime("now", "TimeZone", "UTC", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")));
end
