function filename = exampleFilename(exampleId, galleryIndex)
%EXAMPLEFILENAME Stable, sortable and filesystem-safe gallery filename.

arguments
    exampleId (1,1) string
    galleryIndex (1,1) double {mustBeInteger, mustBePositive}
end

raw = strtrim(exampleId);
if ismissing(raw) || strlength(raw) == 0
    raw = "example";
end
slug = regexprep(lower(raw), "[^a-z0-9._-]+", "-");
slug = regexprep(slug, "[-.]+$", "");
slug = regexprep(slug, "^[-.]+", "");
if strlength(slug) == 0
    slug = "example";
end
slug = extractBefore(slug + " ", min(strlength(slug), 72) + 1);
digest = edaSha256OfText(raw);
filename = compose("%04d_%s--%s.png", galleryIndex, slug, ...
    extractBetween(digest, 1, 10));
end
