local lpeg = require "lpeg"
local P, S, R, V = lpeg.P, lpeg.S, lpeg.R, lpeg.V
local C, Carg, Cb, Cc = lpeg.C, lpeg.Carg, lpeg.Cb, lpeg.Cc
local Cf, Cg, Cmt, Ct = lpeg.Cf, lpeg.Cg, lpeg.Cmt, lpeg.Ct
local tonumber, type, iotype, open = tonumber, type, io.type, io.open
local _ENV = nil
local digit = R"09"

local escape_map = {
    ["\a"] = "\\a",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\v"] = "\\v",
}

local unescape_map = {
    ["\\a"] = "\a",
    ["\\b"] = "\b",
    ["\\f"] = "\f",
    ["\\n"] = "\n",
    ["\\r"] = "\r",
    ["\\t"] = "\t",
    ["\\v"] = "\v",
    ["\\\n"] = "\n",
    ["\\\r"] = "\n",
    ["\\'"] = "'",
    ['\\"'] = '"',
    ["\\\\"] = "\\"
}

local function escape(s)
    return (s:gsub("[\a\b\f\n\r\t\v]", escape_map))
end

local function unescape(s)
    return (s:gsub("\\[abfnrtv'\n\r\"\\]", unescape_map))
end

local function lineno(str, i)
    if i == 1 then
        return 1, 1
    end
    local rest, n = str:sub(1, i):gsub("[^\n]*\n", "")
    return n + 1, #rest
end

local function getffp(subject, position, errorinfo)
    return errorinfo.ffp or position, errorinfo
end

local function report_error()
    local errorinfo = Cmt(Carg(1), getffp) * V"OneWord" / function(e, u)
        e.unexpected = u
        return e
    end
    return errorinfo / function(e)
        local filename = e.filename or ""
        local line, col = lineno(e.subject, e.ffp or 1)
        local unexpected = escape(e.unexpected)
        local s = "%s:%d:%d: Syntax error: unexpected '%s', expecting %s"
        return nil, s:format(filename, line, col, unexpected, e.expected)
    end
end

local function setffp(s, i, t, n)
    if not t.ffp or i > t.ffp then
        t.ffp = i
        t.list = {}
        t.list[n] = n
        t.expected = "'" .. n .. "'"
    elseif i == t.ffp then
        if not t.list[n] then
            t.list[n] = n
            t.expected = "'" .. n .. "', " .. t.expected
        end
    end
    return false
end

local function updateffp(name)
    return Cmt(Carg(1) * Cc(name), setffp)
end

local function T(name)
    return V(name) * V"Skip" + updateffp(name) * P(false)
end

local function symb(str)
    return P(str) * V"Skip" + updateffp(str) * P(false)
end

local function setfield(t, v1, v2)
    if v2 == nil then
        t[#t + 1] = v1
    else
        t[v1] = v2
    end
    return t
end

local function delim_match(subject, offset, c1, c2)
    return c1 == c2
end

local grammar = {
    V"Return" * V"Table" * T"EOF" + report_error();

    Key = T"Number" + T"String" + T"Boolean";
    Value = T"Number" + T"String" + T"Boolean" + V"Table";
    IndexedField = Cg(symb"[" * V"Key" * symb"]" * symb"=" * V"Value");
    NamedField = Cg(T"Name" * symb"=" * V"Value");
    Field = V"IndexedField" + V"NamedField" + V"Value";
    FieldSep = symb"," + symb";";
    FieldList = (V"Field" * (V"FieldSep" * V"Field")^0 * V"FieldSep"^-1)^-1;
    Table = symb"{" * Cf(Ct"" * V"FieldList", setfield) * symb"}";

    LongOpen = "[" * Cg(P"="^0, "openeq") * "[" * P"\n"^-1;
    LongClose = "]" * C(P"="^0) * "]";
    LongMatch = Cmt(V"LongClose" * Cb"openeq", delim_match);
    LongString = V"LongOpen" * C((P(1) - V"LongMatch")^0) * V"LongClose" / 1;

    LongComment = P"--" * V"LongString" / 0;
    LineComment = P"--" * (P(1) - P"\n")^0;
    Comment = V"LongComment" + V"LineComment";

    Skip = (S" \f\n\r\t\v" + V"Comment")^0;
    Return = V"Skip" * (P"return" * -V"NameChar")^-1 * V"Skip";
    EOF = P(-1);

    Keywords = P"and" + "break" + "do" + "elseif" + "else" + "end" +
               "false" + "for" + "function" + "goto" + "if" + "in" +
               "local" + "nil" + "not" + "or" + "repeat" + "return" +
               "then" + "true" + "until" + "while";

    NameStart = R"az" + R"AZ" + P"_";
    NameChar = V"NameStart" + R"09";
    Reserved = V"Keywords" * -V"NameChar";
    Name = -V"Reserved" * C(V"NameStart" * V"NameChar"^0) * -V"NameChar";

    Hex = P"0" * S"xX" * (R"af" + R"AF" + R"09")^1;
    Expo = S"eE" * S"+-"^-1 * digit^1;
    Float = (((digit^1 * P"." * digit^0) + (P"." * digit^1)) * V"Expo"^-1) +
            (digit^1 * V"Expo");
    Int = digit^1;
    Number = C(P"-"^-1 * (V"Hex" + V"Float" + V"Int")) / tonumber;

    True = P"true" * -V"NameChar" * Cc(true);
    False = P"false" * -V"NameChar" * Cc(false);
    Boolean = V"True" + V"False";

    SingleQuotedString = P"'" * C(((P"\\" * P(1)) + (P(1) - S"'\r\n"))^0) * symb"'";
    DoubleQuotedString = P'"' * C(((P'\\' * P(1)) + (P(1) - S'"\r\n'))^0) * symb'"';
    ShortString = V"DoubleQuotedString" + V"SingleQuotedString";
    String = V"LongString" + (V"ShortString" / unescape);

    OneWord = C(V"Name" + V"Number" + V"String" + V"Reserved" + P(1)) + Cc"EOF";
}

local function parse(subject, filename)
    local errorinfo = {subject = subject, filename = filename}
    lpeg.setmaxstack(1000)
    return lpeg.match(grammar, subject, 1, errorinfo)
end

local function parse_file(file_or_filename)
    local file, filename, openerr
    if type(file_or_filename) == "string" then
        filename = file_or_filename
        file, openerr = open(filename)
        if not file then
            return nil, openerr
        end
    elseif iotype(file_or_filename) == "file" then
        file = file_or_filename
    else
        return nil, "Invalid argument #1: not a file handle or filename string"
    end
    local text, readerr = file:read("*a")
    file:close()
    if not text then
        return nil, readerr
    end
    return parse(text, filename)
end

return {
    parse = parse,
    parse_file = parse_file
}
