# Bash quick ref & coding tips

## Unquoted vars

Globbing is disabled so that unquoted vars can contain
special characters. Use `set +f` temporarily when needed
and then `set -f` to disable it back.

If you check your input with `checkvars`, then you don't have to
quote vars that can't contain spaces (which is most vars).
It also makes it easy to see which vars allow spaces and which do not.

Assignments of form `a=$b` or `a=$(cmd)` do not need quoting.

## Unsafe constructs

`[ "$VAR" ]` is not safe (what if VAR is "-z" ?), use `[[ $VAR ]]` instead.

`echo "$VAR"` is not safe (what if VAR is "-n" ?), use `printf "%s\n" "$VAR"` instead.

## Pipefail

`pipefail` is enabled so that failure is not ignored when using `|`.

## Conditionals

```
[[ $VAR ]]            - use instead of [ -n "$VAR" ]
[[ ! $VAR ]]          - use instead of [ -z "$VAR" ]
[[ $A == $B ]]        - use instead of [ "$A" -eq "$B" ]
[[ $A != $B ]]        - use instead of [ "$A" -ne "$B" ]
[[ expr1 || expr2 ]]  - use instead of [ expr1 -o expr2 ]
[[ expr1 && expr2 ]]  - use instead of [ expr1 -a expr2 ]

[[ str =~ regex   ]]  - string matches regex pattern like ^[0-9]+$ etc.
[[ str == extglob ]]  - string contains extglob pattern like *(patt), ?(patt), *(patt)*, etc.

[[ -f file ]]  - file exists
[[ -s file ]]  - file not empty
[[ -d dir  ]]  - dir exists
[[ -e name ]]  - file or dir etc. exists
[[ -w file ]]  - file exists and it's writable
```

## Special vars

```
"$@"  - expand args without word-splitting
$*    - expand args and word-split them
$#    - arg count
$?    - exit code of last command
$!    - PID of last background command
$$    - PID of current process
$IFS  - word splitting separator
$PWD  - current dir
$OLDPWD - prev. current dir
$RANDOM - generate a random positive int16
$LINENO - current line number
```

## Dealing with missing values

```
${var:-default} - default if var is empty
${var:=default} - same but also assigns var to default
${var:+repl}    - use repl if var is non-empty
${var:?err}     - err and exit if var is empty
```

## String ops

```
${var:offset:len} - substring
${var#patt}       - remove prefix
${var##patt}      - remove prefix (longest match)
${var%patt}       - remove suffix
${var%%patt}      - remove suffix (longest match)
${var/patt/repl}  - replace first match with repl
${var//patt/repl} - replace all matches
${var/#patt/repl} - replace prefix
${var/%patt/repl} - replace suffix
```

# Arrays

```
declare -a A   - create array
A=(a b c)      - create array and initialize
A+=(a b c)     - append to array
"${A[@]}"      - expand elements without splitting
```

# Hashmaps

```
declare -A M   - create hashmap
M[key]=val     - assign key
"${M[@]}"      - expand values (random order)
"${!M[@]}"     - expand keys (random order)
```
