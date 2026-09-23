function domains = schemaDomainVocabulary()
%SCHEMADOMAINVOCABULARY The closed set of schema domains.
%
% A domain groups relational objects that are described together. The set is
% closed so that a typo in a domain name fails rather than silently creating a
% domain nobody will ever declare complete.
%
% These ten partition the schema exactly. Measured during Part 1 against the
% committed structural representation: 93 base tables across the first nine,
% 14 views in the tenth, with every object assigned once and none twice.
%
% Domain membership is declared per object, inside the object's own entry.
% There is deliberately no separate domain-to-object registry: a second list of
% which objects belong where would be a second thing to keep true.

domains = [ ...
    "identity_config_provenance"
    "entities_experiment"
    "recordings_geometry"
    "extractors_features"
    "detections_curation"
    "matching_agreement"
    "alignment_external"
    "tracking_acoustic_derived"
    "attribution"
    "views"];
end
