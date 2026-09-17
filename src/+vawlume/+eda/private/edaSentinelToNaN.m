function value = edaSentinelToNaN(raw)
%EDASENTINELTONAN Map the repository's numeric NULL sentinel back to NaN.
%
% MATLAB's Database Toolbox raises while building a result set that contains a
% SQL NULL, so nullable numeric columns are selected as IFNULL(col, 1e308) and
% restored here. The convention follows consilienceFeatureAgreement's
% canonicalValue, which uses the same sentinel and the same 1e307 test.
%
% A stored candidate metric therefore reaches the surface as NaN whether it was
% NULL, NaN, or absent, and the coverage vocabulary reports all three as
% non_finite. No legitimate temporal metric approaches 1e307 seconds.
value = double(raw);
value(value >= 1e307) = NaN;
end
