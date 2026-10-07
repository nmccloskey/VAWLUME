function attributionRequireCallerTransaction(conn, label)
%ATTRIBUTIONREQUIRECALLERTRANSACTION Refuse Transaction="caller" with no open transaction.
%
% In "caller" mode a writer joins the caller's transaction and neither commits
% nor rolls back. With AutoCommit on there is no transaction to join: each row
% would commit on its own while the caller believed the unit atomic, which is the
% failure the mode exists to remove (itinerary 6.9a).

if string(conn.AutoCommit) ~= "off"
    error("vawlume:attribution:TransactionState", ...
        "%s with Transaction=""caller"" requires the caller to have set " + ...
        "AutoCommit off and to own commit and rollback.", label);
end
end
