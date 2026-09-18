function letters = edaFactorLetters(k)
%EDAFACTORLETTERS Design letters A, B, C ... for k factors, in their design order.
%
% The design labels factors by letter because the generator catalogue, the
% defining relation, and every published table of fractional factorials do. The
% mapping from letter to the matching specification's own field name is carried
% beside the design, so a reader never has to guess which parameter "C" was.
if k < 1 || k > 26
    error("vawlume:eda:FactorCountUnsupported", ...
        "Designs are labelled with single letters, so k must be 1 to 26; " + ...
        "got %d.", k);
end
letters = string(num2cell(char('A' + (0:(k - 1)))));
letters = letters(:)';
end
