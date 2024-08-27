#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-

# Cause random havoc in order to test collection of Checkstyle violations.

cd lentic
sed -rf <(echo '
  s~^(import net\.minecraft\.world\.)[A-Za-z]\S+$~&\n&\n\1*;~
  ') -i -- $(git grep -lFe 'import net.minecraft.world.' -- worldedit-sponge/)
