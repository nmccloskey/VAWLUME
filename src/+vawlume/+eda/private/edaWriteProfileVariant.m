function document = edaWriteProfileVariant(source, target, edits, configurationId, options)
%EDAWRITEPROFILEVARIANT Write a profile variant that differs from its source only as declared.
%
% Shared by vawlume.eda.attributionSensitivity and correspondenceSensitivity
% (contract 07 D6). A JSON round-trip would drop null and single-element arrays,
% so the variant is a byte copy of SOURCE with only the edited values and the
% version label "<version>+sens.<configuration_id>" changed.
% Copy SOURCE to TARGET changing only the edited values and the version label.
% Every other byte is the reference's, so the variant differs from the reference
% exactly by its declared factors. Each edit applies inside the top-level member
% SCOPE (parameters, thresholds, pairs) and must match exactly once there (or,
% with AllMatches, at least once); the version label inside "profile".
arguments
    source (1,1) string
    target (1,1) string
    edits (1,1) struct
    configurationId (1,1) string
    options.Scope (1,1) string
    options.AllMatches (1,1) logical = false
end
text = string(fileread(source));
original = jsondecode(text);
label = string(original.profile.profile_version) + "+sens." + configurationId;
text = withinMember(text, "profile", @(part) replaceValue(part, "profile_version", ...
    jsonencode(label), false));
for name = string(fieldnames(edits))'
    text = withinMember(text, options.Scope, @(part) replaceValue(part, name, ...
        edits.(name), options.AllMatches));
end
if isfile(target)
    if string(fileread(target)) ~= text
        error("vawlume:eda:SensitivityFamilyConflict", ...
            "%s exists with different content.", target);
    end
else
    fid = fopen(target, "w");
    fwrite(fid, char(text));
    fclose(fid);
end
document = jsondecode(text);
end

function text = withinMember(text, member, edit)
% Apply EDIT to the value of the top-level JSON member MEMBER only: an object or
% an array, located by matching its brackets outside string literals.
start = regexp(text, '"' + member + '"\s*:\s*[\{\[]', "end", "once");
if isempty(start)
    error("vawlume:eda:SensitivitySpecInvalid", ...
        "The reference file has no %s member.", member);
end
chars = char(text);
depth = 0;
inString = false;
for k = start:numel(chars)
    ch = chars(k);
    if inString
        if ch == '\'
            chars(k + 1) = ' '; % skip the escaped character when scanning
        elseif ch == '"'
            inString = false;
        end
        continue
    end
    if ch == '"'
        inString = true;
    elseif ch == '{' || ch == '['
        depth = depth + 1;
    elseif ch == '}' || ch == ']'
        depth = depth - 1;
        if depth == 0
            stop = k;
            break
        end
    end
end
original = char(text);
part = string(original(start:stop));
text = string(original(1:start - 1)) + edit(part) + string(original(stop + 1:end));
end

function text = replaceValue(text, key, valueJson, allMatches)
scalar = '"(?:[^"\\]|\\.)*"|\[[^\]]*\]|\{[^{}]*\}|-?[0-9.eE+-]+|true|false|null';
pattern = '("' + key + '"\s*:\s*)(' + scalar + ')';
hits = regexp(text, pattern, "match");
if (allMatches && isempty(hits)) || (~allMatches && numel(hits) ~= 1)
    error("vawlume:eda:SensitivitySpecInvalid", ...
        "Expected %s one value of %s in the reference file; found %d.", ...
        string(ternary(allMatches, "at least", "exactly")), key, numel(hits));
end
text = regexprep(text, pattern, "$1" + replace(replace(valueJson, "\", "\\"), "$", "\$"));
end

function value = ternary(condition, a, b)
if condition, value = a; else, value = b; end
end
