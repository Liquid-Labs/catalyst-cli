#!/usr/bin/env bash

# bash strict settings
set -o errexit # exit on errors
set -o nounset # exit on use of uninitialized variable
set -o pipefail

import colors
import echoerr
import lists
import prompt
import real_path
import select
source ./actions/inc.sh
source ./lib/inc.sh
# process global overrides of the form 'key="value"'
while (( $# > 0 )) && [[ $1 == *"="* ]]; do
  eval ${1%=*}="'${1#*=}'"
  shift
done

# see note in lib/utils.sh:colorerr re. SAW_ERROR
# local SAW_ERROR=''
if [[ $# -lt 1 ]]; then
  help --summary-only
  echoerr "Invalid invocation. See usage above."
  exit 1
fi

ensureConfig
mkdir -p "${_CATALYST_ENV_LOGS}"

source ./dispatch.sh

exit 0
