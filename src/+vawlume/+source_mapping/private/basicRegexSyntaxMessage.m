function message = basicRegexSyntaxMessage(pattern)
%BASICREGEXSYNTAXMESSAGE Small structural regex preflight for profile text.
message = "";
pattern = char(string(pattern));

for tokenPattern = {'\(\?<([^>)]*)>', '\(\?P<([^>)]*)>'}
    tokens = regexp(pattern, tokenPattern{1}, 'tokens');
    for index = 1:numel(tokens)
        name = string(tokens{index}{1});
        if isempty(regexp(char(name), '^[A-Za-z][A-Za-z0-9_]*$', 'once'))
            message = "Regex named capture has an invalid name: " + name + ".";
            return
        end
    end
end

escaped = false;
inCharacterClass = false;
groupDepth = 0;
for index = 1:numel(pattern)
    character = pattern(index);
    if escaped
        escaped = false;
        continue
    end
    if character == '\'
        escaped = true;
        continue
    end
    if character == '[' && ~inCharacterClass
        inCharacterClass = true;
        continue
    end
    if character == ']' && inCharacterClass
        inCharacterClass = false;
        continue
    end
    if inCharacterClass
        continue
    end
    if character == '('
        groupDepth = groupDepth + 1;
    elseif character == ')'
        groupDepth = groupDepth - 1;
        if groupDepth < 0
            message = "Regex contains an unmatched closing parenthesis.";
            return
        end
    end
end

if inCharacterClass
    message = "Regex contains an unclosed character class.";
elseif groupDepth > 0
    message = "Regex contains an unclosed parenthesized group.";
elseif escaped
    message = "Regex ends with an unfinished escape sequence.";
end
end
