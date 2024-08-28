#!/bin/sed -zrf
# -*- coding: UTF-8, tab-width: 2 -*-

s!\r!!g
s!<div class="file-violation">!\r&!
s!^[^\r]*\r!!
s!<a href="#top">Back to top</a>.*$!!

s!(<[a-z0-9]+)>!\1 >!ig

s!`!&#x60;!g
s!/lentic/!\r&!g
s!<a( (class|name|href)="[^<>"]*")*>[^<>\r]+\r/lentic/([^<>]+)</a>!\&icon:text-document; `\3`!g
s!\r!!g

s!<t[dh](| [^<>]*)>\s*!| !ig
s!\s*</t[dh]>!\t|!ig
s!\t\|{2} !\t| !g
s!<tr(| [^<>]*)>\s*!\n!ig
s!\s*</tr>!\n!ig

s!</?(th|td)(| [^<>]*)>\s*!\t|\t!ig
s!(</?(html|head|body|meta|title|p|div|tr|th|td)(| [^<>]*)>\s*)+!!ig
s!\n\s+!\n!g

s!\s+(</h3>)!\1\n!ig
s!\s*<h3 [^<>]*>\s*(\&icon:text-document; [^<>]*)</h3>\s*!\n\n### \1\n\n!ig

s!\n<table class="violationlist"[^<>]*>\n(|$\
  )\| Severity\t\| Description\t\| Line Number\t\|\n|$\
  !\n\r<violations>!g
: severity_line_number_table
  s!(\r<violations>)\| ([^\t]+)\t\| ([^\t]+)\t\| ([^\t]+)\t\|\n|$\
    !* \&icon:crosshair;\4 <violation severity=\2> `\3`\n\1!
  s!(\r<violations>)\s*</table>!\n\n\n!
t severity_line_number_table
s!<violation severity=(error)>!\&icon:\1;!g
s!<violation severity=warn(ing|)>!\&icon:warning;!g
s!<violation severity=([^<>]+)>!(\1)!g

s!\s*<table [^<>]*>\s*(\|[^\n]+)(\n\|)!\n\n\1\n\r<table>\1\2!ig
: generic_table_headline
  s!(\r<table>)(\|)!\r\t\2-\1!
  s!(\r<table>)([^\n\|])!-\1!
  s!-?(\r<table>)(\n)!\2!
t generic_table_headline
s!\n\r\t!\n!g
s!\r\t\|!----- |!g
s!\t\|!        |!g
s!\s*</table>\s*!\n\n\n!ig

s!\&icon:crosshair;!⌖!g
s!\&icon:error;!❌!g
s!\&icon:ledger;!📒!g
s!\&icon:text-document;!🖹!g
s!\&icon:warning;!⚠!g

s!\r!««!g
s!^\s+!!
s!\s+$!\n!
