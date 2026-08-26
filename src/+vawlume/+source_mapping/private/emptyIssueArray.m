function issues = emptyIssueArray()
%EMPTYISSUEARRAY Empty source_mapping issue struct array.
issues = struct("severity", {}, "code", {}, "profile_location", {}, "message", {});
end
