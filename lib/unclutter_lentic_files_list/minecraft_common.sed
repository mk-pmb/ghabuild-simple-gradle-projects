#!/bin/sed -urf
# -*- coding: UTF-8, tab-width: 2 -*-

\:/(re|)(build|compuile)/($\
  |classes|$\
  |generated-sources|$\
  |kotlin-dsl|$\
  )(/|$):d

\:/steps/unzipSources/unpacked(/|$):d

