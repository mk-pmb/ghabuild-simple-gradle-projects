#!/bin/sed -urf
# -*- coding: UTF-8, tab-width: 2 -*-

/\-dist\.jar/!d

# sed -nre 's~^#: ~~p' -- jar_filter.sed | ./jar_filter.sed
#: worldedit-fabric-mc1.20-7.2.16-SNAPSHOT.jar
#: worldedit-fabric-mc1.20-7.2.16-SNAPSHOT-dist.jar
#: worldedit-fabric-mc1.20-7.2.16-SNAPSHOT-dist-dev.jar
#: worldedit-fabric-mc1.20-7.2.16-SNAPSHOT-javadoc.jar
#: worldedit-fabric-mc1.20-7.2.16-SNAPSHOT-sources.jar
