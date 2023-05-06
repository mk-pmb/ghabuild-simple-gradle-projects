#!/bin/sed -rf
# -*- coding: utf-8, tab-width: 2 -*-

/^\s*java\.withSourcesJar\(\)$/s~\S~// &~
/^task sourcesJar\(/,/^\}$/s~^~// ~

# Sabotage the Loom cache lookup for the outdated version of tweed
/^\s*maven \{/{
  : more_maven
  /\}$/!{N; b more_maven}
  /name "Siphalor's Maven"/s~^|\n~&// ~g
}

# /^\s*include\(modApi\("de\.siphalor\.tweed4:tweed4-/s~\S~// &~
