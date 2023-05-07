#!/bin/sh
mkdir --parents build/libs
zip -j0 build/libs/dummy-v0.0.0.jar -- ../tmp.variation.*
