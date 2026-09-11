function agreementAssertPatternIdentifiers(conn, extractorRuns)
%AGREEMENTASSERTPATTERNIDENTIFIERS Refuse identifiers that would make a pattern ambiguous.
%
% Arbitrary-N agreement reports which unordered extractor pairs support a
% component by flattening sets of identifiers into delimited strings. Four
% conventions are in use across three value families:
%
%   extractor_key    -> extractor_pair_key            'a--b'
%                       extractor_set_key             'a|b|c'
%                       supported_extractor_pair_pattern
%                                                     'a--b|a--c'
%   extractor_name   -> extractor_pair_label          'A -- B'
%                       supported_extractor_pair_label
%                                                     'A -- B;A -- C'
%                       MATLAB pair_label             'A|B'
%   run_key          -> extraction_run_set_key        'r1|r2|r3'
%
% Note that the SQL pattern joins pairs with '|' while the MATLAB pair label
% joins the two sides of one pair with '|'. The same character therefore means
% different things on the two surfaces, which is exactly why an identifier
% carrying it cannot be parsed back consistently.
%
% None of the three source columns is constrained by the schema, and
% extractor_name in particular is free-form human-readable text. A collision
% would not raise: it would silently yield a wrong population from an exact
% pattern query or a coarse K-of-possible filter, which is the worst failure
% available to an analysis-ready filter.
%
% The check lives here, at the composition chokepoint, rather than as a schema
% CHECK on extractors. The ambiguity is created when identifiers are flattened
% into patterns, not when an extractor is registered; a CHECK would also leave
% the MATLAB-side joins unguarded and would constrain a table that predates this
% layer.
%
% This refuses composition. It never rewrites or escapes an identifier, because
% a caller reading a pattern has to be able to map it back to the extractor keys
% they registered.

arguments
    conn
    extractorRuns table
end

assertFree(extractorRuns.extractor_name, "extractor name");
assertFree(extractorRuns.run_key, "extraction run key");
assertFree(extractorKeys(conn, extractorRuns), "extractor key");
end

function keys = extractorKeys(conn, extractorRuns)
idList = strjoin(string(unique(extractorRuns.extractor_id)'), ",");
rows = fetch(conn, "SELECT extractor_key FROM extractors " + ...
    "WHERE extractor_id IN (" + idList + ") ORDER BY extractor_id");
keys = presentText(rows.extractor_key);
end

function assertFree(values, valueKind)
delimiters = reservedDelimiters();
values = presentText(values);
for index = 1:numel(values)
    % Tested one delimiter at a time: contains() against a pattern array
    % answers "any of these" with a single logical, which cannot say which
    % delimiter was found, and the message is more useful when it names it.
    matched = arrayfun(@(d) contains(values(index), d), delimiters);
    found = delimiters(matched);
    if ~isempty(found)
        error("vawlume:agreement:IdentifierDelimiterConflict", ...
            "The %s '%s' contains the reserved delimiter %s. Extractor " + ...
            "pair and set identifiers are composed by joining these values " + ...
            "with '--', '|' and ';', so a value containing one of them makes " + ...
            "the resulting pattern ambiguous and would silently return the " + ...
            "wrong population.", valueKind, values(index), ...
            strjoin("'" + found(:)' + "'", ", "));
    end
end
end

function value = reservedDelimiters()
value = ["--", "|", ";"];
end

function value = presentText(raw)
value = string(raw);
value(ismissing(value)) = "";
end
