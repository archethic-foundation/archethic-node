#!/bin/bash
mix hex.outdated --within-requirements 1>/dev/null || echo 'Updates available!'