function value = acousticPresentText(raw)
%ACOUSTICPRESENTTEXT Normalize fetched text, mapping missing to empty text.
value = string(raw);
value(ismissing(value)) = "";
end
