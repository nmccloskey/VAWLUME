function pattern = matlabRegexPattern(pattern)
%MATLABREGEXPATTERN Translate accepted profile regex syntax for MATLAB.
pattern = string(pattern);
pattern = regexprep(pattern, '\(\?P<([A-Za-z][A-Za-z0-9_]*)>', '(?<$1>');
end
