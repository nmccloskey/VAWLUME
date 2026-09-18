function letters = edaLettersOf(text)
%EDALETTERSOF Split "ABC" into a ROW string array ["A" "B" "C"].
%
% A row, deliberately and load-bearingly. MATLAB's for-loop iterates over the
% COLUMNS of its argument, so `for name = ["A";"B";"C"]` runs once with the whole
% column rather than three times with each letter. A generator parser that made
% that mistake would silently resolve the wrong factor column and produce a
% design that is neither balanced nor orthogonal - which is exactly how it was
% caught here.
letters = string(num2cell(char(strtrim(string(text)))));
letters = reshape(letters, 1, []);
end
