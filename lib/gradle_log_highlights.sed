#!/bin/sed -nurf
# -*- coding: UTF-8, tab-width: 2 -*-

/^\* What went wrong:$/{
  : went_wrong
  /\n\* Try:$/!{N;b went_wrong}
  s~\n~ =\a=&~
  s~^\*~=\a=~
  s!=\a=!--------------------!g
  s~\n+[^\n]+$~\n~
  p
}


/^\/\S+\.java:[0-9]+:/{
  # Matching line: Filename, line number, error message
  p;n
  # line 2: The offending code line, verbatim
  p;n
  # line 3: Position indicator: Lots of spaces, then a circumflex.
  /^ *\^$/{s~ ~-~g;s~$~\n~;p;n}
}


/^> Task \S+ FAILED/p














# scroll
