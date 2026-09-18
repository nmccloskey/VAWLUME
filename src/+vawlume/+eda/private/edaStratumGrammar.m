function parsed = edaStratumGrammar(specs)
%EDASTRATUMGRAMMAR Parse contract §I's recording-level stratum field grammar.
%
% PARSED = EDASTRATUMGRAMMAR(SPECS) turns each field specification into a row
% naming its KIND and the NAME it selects on, refusing anything the grammar does
% not admit.
%
%   recording_attribute:<name>   recording_attributes value for that recording
%   entity_attribute:<name>      entity_attributes value via recording_entity_links
%   epoch:<epoch_type>           recording_epochs.epoch_name of that type
%   recording                    recordings.native_recording_id
%
% ONE PARSER, because this is the only stratum grammar in the MVP. A second
% reading of the same strings would eventually disagree with this one about which
% field a spec names, and the disagreement would surface as a sampling bias with
% no visible cause.
%
% SUPPORT-PATTERN AND EXTRACTOR-SET FIELDS ARE REFUSED BY NAME, not merely absent
% from the table. They were in the calibration-era grammar, so a caller carrying
% an old configuration forward will write one, and "unknown field kind" would read
% as a typo rather than as the deliberate deletion it is. Support pattern is an
% OUTPUT of the correspondence analysis the subset exists to probe: stratifying
% on it would condition the sample on the thing being measured.

arguments
    specs string
end

specs = specs(:);
kinds = strings(numel(specs), 1);
names = strings(numel(specs), 1);

for index = 1:numel(specs)
    spec = strtrim(specs(index));
    if ismissing(spec) || strlength(spec) == 0
        error("vawlume:eda:StratumFieldInvalid", ...
            "Stratum field %d is empty. Every field names one of: %s.", ...
            index, strjoin(grammarKinds(), ", "));
    end
    assertNotDeletedField(spec);
    [kinds(index), names(index)] = parseOne(spec, index);
end

parsed = table(specs, kinds, names, ...
    VariableNames=["field", "kind", "name"]);

[distinct, ~, grouping] = unique(parsed.field);
duplicated = distinct(accumarray(grouping, 1) > 1);
if ~isempty(duplicated)
    error("vawlume:eda:StratumFieldDuplicated", ...
        "Stratum field(s) %s were supplied more than once. A repeated field " + ...
        "would be considered twice and could be reported both used and " + ...
        "rejected.", strjoin(duplicated', ", "));
end
end

function [kind, name] = parseOne(spec, index)
if spec == "recording"
    kind = "recording";
    name = "native_recording_id";
    return
end
separator = strfind(spec, ":");
if isempty(separator)
    error("vawlume:eda:StratumFieldInvalid", ...
        "Stratum field %d ('%s') is not in the grammar. Write " + ...
        "'recording', or one of %s followed by ':' and a name.", ...
        index, spec, strjoin(qualifiedKinds(), ", "));
end
kind = extractBefore(spec, separator(1));
name = strtrim(extractAfter(spec, separator(1)));
if ~ismember(kind, qualifiedKinds())
    error("vawlume:eda:StratumFieldInvalid", ...
        "Stratum field %d ('%s') names kind '%s', which is not in the " + ...
        "grammar. Admitted kinds: %s.", ...
        index, spec, kind, strjoin(grammarKinds(), ", "));
end
if strlength(name) == 0
    error("vawlume:eda:StratumFieldInvalid", ...
        "Stratum field %d ('%s') names kind '%s' with no attribute or " + ...
        "epoch type after the colon.", index, spec, kind);
end
end

function assertNotDeletedField(spec)
%ASSERTNOTDELETEDFIELD Refuse the two fields the contract deleted, by name.
deleted = ["support_pattern", "extractor_set"];
head = extractBefore(spec + ":", ":");
if ismember(head, deleted) || ismember(spec, deleted)
    error("vawlume:eda:StratumFieldForbidden", ...
        "Stratum field '%s' is deleted from the grammar. A subset may not " + ...
        "be stratified by an extractor-support or extractor-set field: " + ...
        "those are outputs of the correspondence analysis this subset " + ...
        "exists to probe, so stratifying on one would condition the sample " + ...
        "on the quantity being measured. Admitted kinds: %s.", ...
        spec, strjoin(grammarKinds(), ", "));
end
end

function value = qualifiedKinds()
value = ["recording_attribute", "entity_attribute", "epoch"];
end

function value = grammarKinds()
value = [qualifiedKinds(), "recording"];
end
