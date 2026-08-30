function value = consilienceAlgorithm()
%CONSILIENCEALGORITHM Identity of the agreement computation itself.
%
% Separate from the matching algorithm version. Changing how agreement is
% computed must produce a new derived analysis rather than silently altering the
% meaning of stored statistics, so this version is part of the child analysis key.

value = struct(key="detection_and_feature_agreement", version="0.1.0");
end
