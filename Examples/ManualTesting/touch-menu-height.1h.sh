#!/bin/bash

# <xbar.title>Touch Menu Height Demo</xbar.title>
# <xbar.desc>Static rows for comparing native and fold-header heights with touch and pointer input.</xbar.desc>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>
# <swiftbar.collapseOnClose>true</swiftbar.collapseOnClose>

cat <<'MENU'
Touch height demo | dropdown=false
---
Native row above
Fold section | fold=true badge=2
--First child
--Second child
Native row below
Submenu
--Native submenu row
--Nested fold | fold=true badge=1
----Nested child
MENU
