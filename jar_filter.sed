#!/bin/sed -urf
# -*- coding: UTF-8, tab-width: 2 -*-

/(-dev|-shadow|-sources)+\.jar$/d
/-fabric\.jar$/!d
