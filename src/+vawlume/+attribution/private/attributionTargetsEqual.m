function value = attributionTargetsEqual(first, second)
%ATTRIBUTIONTARGETSEQUAL Compare target identity, excluding storage metadata.

if height(first) ~= height(second)
    value = false;
    return
end
names = ["detection_id", "consensus_event_id", "agreement_group_id"];
value = true;
for name = names
    left = first.(name);
    right = second.(name);
    value = value && all((isnan(left) & isnan(right)) | left == right);
end
value = value && all(first.agreement_extent_method == ...
    second.agreement_extent_method);
end
