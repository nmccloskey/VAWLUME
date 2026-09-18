function value = edaResponseVocabulary()
%EDARESPONSEVOCABULARY The screen's response families, and what qualifies each.
%
% Several transparent measures, never one score. Every row of the response table
% names one of these, so a consumer can filter on the name rather than parsing a
% label, and a new response is a new row rather than a new column.
name = [ ...
    "detections_considered"
    "pairwise_match_groups"
    "agreement_groups_total"
    "agreement_groups_by_member_count"
    "agreement_groups_by_extractor_count"
    "support_pattern_groups"
    "support_pattern_fraction"
    "coarse_support_groups"
    "extractor_unique_groups"
    "extractor_unique_fraction"
    "ambiguous_groups"
    "unambiguous_one_to_one_groups"
    "group_change_from"
    "group_change_to"
    "group_retention_fraction"];
qualifierKind = [ ...
    "extractor_key"
    "extractor_pair_key"
    ""
    "member_count"
    "extractor_count"
    "support_pattern"
    "support_pattern"
    "supported_pair_count"
    "extractor_key"
    "extractor_key"
    ""
    ""
    "change_class"
    "change_class"
    ""];
secondaryKind = [ ...
    ""
    "match_type"
    ""
    ""
    ""
    ""
    ""
    ""
    ""
    ""
    ""
    ""
    "baseline_configuration_id"
    "baseline_configuration_id"
    "baseline_configuration_id"];
valueKind = [ ...
    "count"; "count"; "count"; "count"; "count"; "count"; "fraction"; ...
    "count"; "count"; "fraction"; "count"; "count"; "count"; "count"; ...
    "fraction"];
value = table(name, qualifierKind, secondaryKind, valueKind, ...
    VariableNames=["response", "qualifier_kind", "secondary_kind", ...
    "value_kind"]);
end
