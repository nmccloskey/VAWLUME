function tf = hasProfileField(container, field)
%HASPROFILEFIELD True when a decoded profile struct has a nonempty field.
tf = isstruct(container) && isfield(container, char(field)) && ...
    ~isempty(container.(char(field)));
end
