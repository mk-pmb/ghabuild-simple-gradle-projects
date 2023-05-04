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
