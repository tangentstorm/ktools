/
/ k grammar
/
\d .kg  /-- k grammar -----------------------------------------

/-- perl-compatible regular experessions
/ the parse engine could be extended to do everything pcre can do
/ without much effort, but this gives us a little nicer syntax.
/ docs: http://projects.1010data.com/downloads/pcre/doc/pcre_8c.html
re.dll: "d:/srv/1010data/branches/test/os/w64/lib/pcre64.dll"
re.pcreMatch: dll 2: ("kpcre_match"; 3) / (needle, haystack, list of options) -> list of matches
re.tearDown: dll 2: ("kpcre_tearDown"; 0)
re.match:{**re.pcreMatch{x;y;()}}

/-- grammar combinators ----------------------------------------
/ These are just helpers to build an AST to describe the grammar.

opt:{(`opt;x)} / "optional"     = regex: x?
rep:{(`rep;x)} / "repeat"       = regex: x+
orp:{(`orp;x)} / opt + rep      = regex: x*
alt:{(`alt;x)} / "alternatives" = regex: x[0] | x[1] | ... x[(#x)-1]

/ -- tokens ---------------------------------------------------

t.SPACE: "\s+"
t.ADV:   "'|':|/:|\\\\:"
t.COMMENT: "/[^\\r\\n]+"
t.COMMAND: "\\[^\\r\\n]+"
t.PRIM: "[~!@#$%\\^&*+<>|,?=_]:?|\\d:" / [;:.\-] are also primitives, but handled specially
t.IDENT: "[a-zA-Z_]+"
t.STRING: "\\\"([^\\\"]|\\.)*\\\""
t.NL: "\\n"
t.SEMI: ";"; t.COLON: ":"; t.DOT: "\\."; t.DASH: "-"; t.AT: "@"
t.LPAREN: "\\("; t.RPAREN: "\\)"
t.LBRACE: "\\{"; t.RBRACE: "\\}"
t.LBRACK: "\\["; t.RBRACK: "\\]"
t.IF: "if\\b"; t.WHILE: "while\\b"; t.DO: "do\\b"


/ -- parse rules ----------------------------------------------

p.k: orp(`item)
p.item: alt(`line; `cmd; `NL)
p.cmd: (`COMMAND; opt `COMMENT; `NL)
p.line: (opt `stmts; opt `COMMENT; `NL)
p.stmts: (`stmt; orp(`SEMI; `stmt))
p.block: (orp `item; opt `stmts) / so we can have stuff on the last line, before the end brace/bracket/whatever
p.stmt: alt(`ifStmt; `doStmt; `whileStmt; `define; `expr; `) / last is empty statement
p.define: (`lvalue; `COLON; `expr)
p.expr: rep(alt(`amend; `cond; `value; rep `op; `LPAREN; `expr; `RPAREN; `ADV))
p.op: ((`PRIM; `DOT; `COLON; `DASH; `IDENT); `tail)
p.value: alt(`lvalue; ((`lambda; `noun); `tail))
p.lvalue: (`IDENT; `tail)
p.lambda: (`RBRACE; opt `sig; `block; `RBRACE)
p.sig: (`LBRACE; opt(`IDENT; orp(`SEMI; `IDENT)); `RBRACK)
p.noun: alt(`STRING; (rep `num); (rep `SYM); `list; `dict)
p.num: (opt `DASH; `INT; `RAT)
p.list: (`LPAREN; `block; `RPAREN)
p.dict: (`DOT; `LPAREN; orp`entry; `RPAREN)
p.entry: (`LPAREN; `expr; `SEMI; `expr; opt(`SEMI; opt`expr); `RPAREN)
p.tail: orp(alt(`attr; `index; `ADV))
p.attr: (`DOT; `IDENT)
p.index: (`LBRACK; `block; `RBRACK)
p.amend: (alt `DOT `AT; `LBRACK; `block; `RBRACK)
p.cond: (`COLON; `LBRACK; `block; `RBRACK)
p.ifStmt: (`IF; `LBRACK; `block `RBRACK)
p.doStmt: (`DO; `LBRACK; `block `RBRACK)
p.whileStmt: (`WHILE; `LBRACK; `block; `RBRACK)

/ -- data structure for parse state ---------------------------

init:{[text] / init -> parse state (AST builder)
    s.text: text     / the remaining text to parse
    s.here: ()       / current node in the AST
    s.path: ()}      / stack of 'here' lists
emit:{@[x; `here; x.here,y]}
drop:{@[x; `here; -1 _ x.here]}
node:{@[x; `path`here; ((x.here;x.path); ())]}
done:{@[x; `path`here; (1_x.path; *x.path)]}
take:{@[x; `text; y _ x.text]}

/ -- grammar interpreter --------------------------------------

skipws:{[s] / skip whitespace to reach start of next token.
    m: .[g.rgx; (t.SPACE;s); :]
    if[0=m 0; :drop[m 1]] / matched a space, so just remove it from output
    :s} / no space, so nothing to do

g.lit:{[txt; s] / g.lit : match a string literal (unused)
    s:skipws[s]
    if[s.text[!#txt]~txt;
        :keep[take[s;#txt];,txt]]
    '"failed to match: ",5:txt}

g.rgx:{[rgx; s] / g.rgx : match a perl-compatible regular expression:
    / ^ is automatically inserted in front of the pattern so that we
    / only match on the start of the text. Also, leading spaces are ignored.
    s:skipws[s]
    m:re.match["^",rgx; s.text]
    / if it fails, we should just get a 0-length match, so m[0;0] should always be 0
    if[~0=m[0;0]; '"unexpected result from re.match:",5:m]
    / if it does match, m[1;0] should be the length
    if[~0=len:m[1;0]; :emit[take[s;len]; *(0,len)_s.text]]
    '"failed to match regex: ",5:rgx}

g.emp:{[r; s] s} / always match, consume nothing, return state unchanged.

g.opt:{[r; s] g.alt[(r;,`emp); s]}

g.rep:{[r; s] s:match[r;s]           / require at least one match
    while[~*m: .[match; (r;s); :]    / then keep matching until we fail
        s:m 1]
    :s}

g.orp:{[r; s] g.opt[rep[r; s]]}     / orp = opt rep

g.alt:{[r; s]
    i: 0; found: 0
    while[(i<#r) & ~found
        m: .[match; (r i; s); :]
        found: 0=*m
        i+:1]
    if[found; :m 1]
    '"none of the alternatives matched: ", 5:r}

match:{[r;s] /.kg.match
    / (top level dispatch for grammar interpreter)
    / r.rule; s:state -> ast (or 'signal on fail)
    / rule ::= symbol | [ rule*]
    if[4=4:r / a symbol should reference either a token (upper case) or parse rule (lower case)
        :[rul _in !t; :g.rgx[t@r; s]
          rul _in !p; :match[p@r; s]
          '"invalid reference:",5:r]]
    / still here. must be a list
    if[0=#r; '"invalid rule (got empty list)"]
    h:*r; typ:4:h
    if[(typ=4) & h _in !g; :(g@h)[1_r; s]] / special symbol: call g.opt/whatever on tail of list
    :g.seq[r;s]}   / otherwise parse as sequence

parse:{[text] /.kg.parse
    / match the top-level grammar rule for k
    / src:str -> ast
    :match[r.k; init[text]]}
