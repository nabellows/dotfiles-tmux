# Today I learned (tmux edition)...
* Braces are dope, can use braces in if-shell, etc to avoid horrible quoting
* if-shell *-F* does NOT run the command as shell, it ONLY checks that the string is not: empty or "0"
  * if-shell always expands format strings even without -F
