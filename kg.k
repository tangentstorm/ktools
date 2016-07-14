/
/ k grammar
/
\d .kg  /-- k grammar -----------------------------------------

/-- perl-compatible regular experessions
/ the parse engine could be extended to do everything pcre can do
/ without much effort, but this gives us a little nicer syntax.
/ docs: http://projects.1010data.com/downloads/pcre/doc/pcre_8c.html
re.dll: "v:/admin2/os/w64/lib/pcre64.dll"
re.pcreMatch: re.dll 2: ("kpcre_match"; 3) / (needle, haystack, list of options) -> list of matches
re.tearDown: re.dll 2: ("kpcre_tearDown"; 0)
re.match:{
    /cut:32&(#y)-1; `0:"| re.match[",(5:x),"; ",(5:* (0;cut) _ y),:[cut<#y;"";"..."],"]\n"
    m:**re.pcreMatch[x;y;(,`first)]
    /re.tearDown[]
    :m}

/-- grammar combinators ----------------------------------------
/ These are just helpers to build an AST to describe the grammar.

opt:{(`opt;x)} / "optional"     = regex: x?
rep:{(`rep;x)} / "repeat"       = regex: x+
orp:{(`orp;x)} / opt + rep      = regex: x*
alt:{(`alt;x)} / "alternatives" = regex: x[0] | x[1] | ... x[(#x)-1]

/ -- tokens ---------------------------------------------------

t.SPACE: "[ \\t]+" / spaces or tabs, but not newlines (because those are special and act like semicolons)
t.ADV:   "'|':|/:|\\\\:"
t.COMMENT: "/[^\\r\\n]+"
t.COMMAND: "\\[^\\r\\n]+"
t.PRIM: "[~!@#$%\\^&*+<>|,?=_]:?|\\d:" / [;:.\-] are also primitives, but handled specially
t.IDENT: "[a-zA-Z_]+"
t.STRING: "\\\"([^\\\"]|\\.)*\\\""
t.NL: "[\\n\\r]+"
t.SEMI: ";"; t.COLON: ":"; t.DOT: "\\."; t.DASH: "-"; t.AT: "@"
t.LPAREN: "\\("; t.RPAREN: "\\)"
t.LBRACE: "\\{"; t.RBRACE: "\\}"
t.LBRACK: "[[]"; t.RBRACK: "\\]"
t.IF: "if\\b"; t.WHILE: "while\\b"; t.DO: "do\\b"
t.NUM: "-?\\d+(\\.\\d+)?"; t.SYM:"`(",t.IDENT,"|",t.STRING,")"

/ -- parse rules ----------------------------------------------

p.k: orp(`item)
p.item: alt(`line; `cmd; `NL)
p.cmd: (`COMMAND; opt`COMMENT; `NL)
p.line: (opt`stmts; opt`COMMENT; `NL)
p.stmts: (`stmt; orp(`SEMI; `stmt))
p.block: (orp`item; opt`stmts) / so we can have stuff on the last line, before the end brace/bracket/whatever
p.stmt: opt(alt(`ifStmt `doStmt `whileStmt `define `expr))
p.define: (`lvalue `COLON `expr)
p.expr: rep(alt(`amend; `cond; `value; (rep `op); (`LPAREN; `expr; `RPAREN); `ADV))
p.op: (alt(`PRIM `DOT `COLON `DASH `IDENT); `tail)
p.value: alt(`lvalue; ((alt `lambda `noun); `tail))
p.lvalue: (`IDENT `tail)
p.lambda: (`LBRACE; (opt `sig); `block; `RBRACE)
p.sig: (`LBRACK; opt(`IDENT; orp(`SEMI; `IDENT)); `RBRACK)
p.noun: alt(`STRING; (rep `NUM); (rep `SYM); `list; `dict)
p.list: (`LPAREN; `block; `RPAREN)
p.dict: (`DOT; `LPAREN; (orp`entry); `RPAREN)
p.entry: (`LPAREN; `expr; `SEMI; `expr; opt(`SEMI; (opt`expr)); `RPAREN)
p.tail: orp(alt(`attr `index `ADV))
p.attr: (`DOT `IDENT)
p.index: (`LBRACK `block `RBRACK)
p.amend: ((alt `DOT `AT); `LBRACK; `block; `RBRACK)
p.cond: (`COLON; `LBRACK; `block; `RBRACK)
p.ifStmt: (`IF; `LBRACK; `block; `RBRACK)
p.doStmt: (`DO; `LBRACK; `block; `RBRACK)
p.whileStmt: (`WHILE; `LBRACK; `block; `RBRACK)

/ -- data structure for parse state ---------------------------

init:{[text] / init -> parse state (AST builder)
    s.text: text     / the remaining text to parse
    s.here: ()       / current node in the AST
    s.path: ()       / stack of 'here' lists
    :s}
emit:{@[x; `here; :; :[_n~x.here; ,y; x.here,y]]}
/drop:{@[x; `here; :; -1 _ x.here]}
node:{@[x; `path`here; :; (((,x.here),x.path); _n) ]}
done:{@[x; `path`here; :; (-1 _ x.path; ((*x.path),x.here))]}
take:{@[x; `text; :; y _ x.text]}


/ -- pretty printer for ASTs ----------------------------------

join:{ 1 _ ,/ x,'y }
pps:{t:4:x / pps : pretty print to string
    :[-3=t; :5:x                       / strings
      ~0<t; :"(",join[" ";_f' x],")"   / other lists
       4=t; :"`",$x                    / symbols
       :5:x ]}                         / others
pp:{`0:pps[x.here],"\n"}

/ -- grammar interpreter --------------------------------------

skipws:{[s] / skip whitespace to reach start of next token.
    m:re.match["^",t.SPACE; s.text]
    if[0<len:m[1;0]; :take[s;len]] / strip out the whitespace
    :s} / no space, so nothing to do

g.lit:{[txt; s] / g.lit : match a string literal (unused)
    s:skipws[s]
    if[s.text[!#txt]~txt;
        :emit[take[s;#txt];,txt]]
    '"failed to match: ",5:txt}

g.tok:{[nm; rgx; s] / g.rgx : match a perl-compatible regular expression with name nm
    / ^ is automatically inserted in front of the pattern so that we
    / only match on the start of the text. Also, leading spaces are ignored.
    s:skipws[s]
    m:re.match["^",rgx; s.text]
    / if it fails, we should just get a 0-length match, so m[0;0] should always be 0
    if[~0=m[0;0]; '"unexpected result from re.match:",5:m]
    / if it does match, m[1;0] should be the length
    if[~0=len:m[1;0]; :emit[take[s;len]; ,(nm; *(0,len) _ s.text)]]
    '"failed to match token `",($nm),": ",5:rgx}

g.emp:{[r; s] :s} / always match, consume nothing, return state unchanged.

g.opt:{[r; s] :g.alt[(r;`emp`); s]}

g.rep:{[r; s]
    s:match[r;s]                      / require at least one match
    while[0=*m: .[match; (r;s); :]    / then keep matching until we fail
        s:m 1]
    :s}

g.orp:{[r; s] :g.opt[rep[r]; s]}     / orp = opt rep

g.alt:{[r; s]
    / `0:"| alt:",(5:r),"\n"
    i: 0; found: 0
    while[(i<#r) & ~found
        m: .[match; (r i; s); :]
        / \((r i); "->"; m)
        found: 0=*m
        i+:1]
    if[found; :m 1]
    '"none of the alternatives matched: ", 5:r}

g.seq:{[r; s] i:0
    while[(i<#r); / match every item, in sequence
        s:match[r i; s]
        i+:1]
    :s}

g.grp:{[tag;r;s]  / create a new node, and emit the name as a header
    s:emit[node[s];tag]
    s:match[r;s]
    :done[s]}

g.rul:{[nm;r;s]  / rul[`name;rule;state]
    if[0=*m:.[match;(r;s);:]; :m 1]
    '"failed to match rule `",($nm),": ",$m 1}

match:{[r;s] / .kg.match
    / `0:"| match: ",(5:r),"\n"
    / (top level dispatch for grammar interpreter)
    / r:rule; s:state -> state | 'err        where  rule ::= symbol | [ rule*]
    if[4=4:r / a symbol should reference either a token (upper case) or parse rule (lower case)
        :[r _in !t; :g.tok[r; t@r; s]
          r _in !p; :g.rul[r; p@r; s]
          '"invalid reference:",5:r]]
    / still here. must be a list
    if[0=#r; '"invalid rule (got empty list)"]
    h:*r; typ:4:h
    if[(typ=4) & h _in !g; :(g@h)[r 1; s]] / special symbol: call g.opt/whatever on tail of list
    :g.seq[r;s]}   / otherwise parse as sequence

parse:{[text] /.kg.parse
    / match the top-level grammar rule for k
    / src:str -> ast
    :match[p.k; init[text,"\n"]]}


/-- tests ----------------------------------------------

chek:{[t;msg] if[~t; 'msg]} / check assertion
cheq:{chek[x~y; "expected: ",($x),"\nbut got: ",($y),"\n"]} / check equality
chkm:{m:re.match[x;y]; chek[m[1;0]>0; "expected /",x,"/ to match ",5:y]} / does the regex match the string? (must match 1+ char)
chka:{m:.[match; (x; init[y]); :] / parse y against rule x and check that resulting ast looks like z
    chek[~m 0; "expected rule ",pps[x]," to match ",5:y]
    if[~z~_n; cheq[z; pps ((m 1).here)]]}
chkp:chka[;;_n] / just check that the parse succeeded

unittest:{ / TODO: make these into actual unit tests... :)

    a:init[`]; chek[()~a.path; "a.path?"]
    b:node[a]; chek[(,())~b.path; "b.path?"]; chek[_n~b.here; "b.here?"]
    c:done[b]; chek[()~c.path; "c.path?"];    chek[(,_n)~c.here; "c.here?"]

    s:skipws init[,"\n"]; chek[s.text~,"\n"; "should not consume \\n as whitespace!"]

    chkm["^a";"abc"]
    chkp[(`LBRACK; `RBRACK); "  [ ]  "]
    chkp[(`LBRACK; `RBRACK); "[]"]
    chkp[`NL; ,"\n"]
    chkp[`COMMENT`NL; "/ hello world?\n"]
    chkp[`NUM; " 2+2 "]
    chkp[`expr; " 2+2 "]
    chkp[`expr; "f[!2+2]"]
    pp match[p.k; init[5:_f]] / check this very function for parsability
    / m:parse[6:"kg.k"] check this whole file...
}

unittest[]
