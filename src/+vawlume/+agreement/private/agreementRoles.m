function roles = agreementRoles()
%AGREEMENTROLES The role labels this layer writes, in one place.
%
% assignment_role 'agreement_spec' is already taken: the pairwise consilience
% child run uses it to link the *matching* specification that produced the
% statistics. Reusing it for the arbitrary-N policy would put two different
% policies under one role name, so this layer declares its own.
roles = struct( ...
    specification="multi_extractor_agreement_spec", ...
    extraction_input="agreement_input", ...
    source_analysis="pairwise_source");
end
