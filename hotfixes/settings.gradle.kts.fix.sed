#!/bin/sed -urf
# -*- coding: UTF-8, tab-width: 2 -*-

# Build only the Fabric part, to avoid this Forge failure:
# https://github.com/EngineHub/WorldEdit/issues/2336
# and maybe also save some time.

/^listOf/s~"(forge)", ~~g
/-mod"/d
