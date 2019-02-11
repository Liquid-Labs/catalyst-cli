runPackageScript() {
  local TMP
  TMP=$(setSimpleOptions IGNORE_MISSING SCRIPT_ONLY -- "$@") \
    || ( contextHelp; echoerrandexit "Bad options." )
  eval "$TMP"

  local ACTION="$1"; shift

  cd "${BASE_DIR}"
  if cat package.json | jq -e "(.scripts | keys | map(select(. == \"$ACTION\")) | length) == 1" > /dev/null; then
    npm run-script "${ACTION}"
  elif [[ -n "$SCRIPT_ONLY" ]] && [[ -z "$IGNORE_MISSING" ]]; then # SCRIPT_ONLY is a temp. workaround to implement future behaior. See note below.
    echoerrandexit "Did not find expected NPM script for '$ACTION'."
  elif [[ -z "$SCRIPT_ONLY" ]]; then
    # TODO: drop this; require that the package interface with catalyst-scripts
    # through the the 'package-scripts'. This will avoid confusion and also
    # allow "plain npm" to run more of what can be run. It will also allow users
    # to override the scripts if they really want to. (But we should catch) that
    # on an audit.
    local CATALYST_SCRIPTS=$(npm bin)/catalyst-scripts
    if [[ ! -x "$CATALYST_SCRIPTS" ]]; then
      # TODO: offer to install and re-run
      echoerr "This project does not appear to be using 'catalyst-scripts'. Try:"
      echoerr ""
      echoerrandexit "npm install --save-dev @liquid-labs/catalyst-scripts"
    fi
    # kill the debug trap because if the script exits with an error (as in a
    # failed lint), that's OK and the debug doesn't provide any useful info.
    "${CATALYST_SCRIPTS}" "${BASE_DIR}" $ACTION || true
  fi
}

requireNpmCheck() {
  # TODO: offer to install
  if ! which -s npm-check; then
    echoerr "'npm-check' not found; could not check package status. Install with:"
    echoerr ''
    echoerr '    npm install -g npm-check'
    echoerr ''
    exit 10
  fi
}

packagesVersionCheckManageIgnored() {
  local IPACKAGES
  if [[ -n "$IGNORE" ]]; then
    local LIVE_PACKAGES=`echo "$PACKAGE" | jq --raw-output '.dependencies | keys | @sh' | tr -d "'"`
    for IPACKAGE in $IGNORED_PACKAGES; do
      LIVE_PACKAGES=$(echo "$LIVE_PACKAGES" | sed -Ee 's~(^| +)'$IPACKAGE'( +|$)~~')
    done
    if (( $# == 0 )); then # interactive add
      PS3="Exclude package: "
      selectDoneCancel IPACKAGES $LIVE_PACKAGES
    else
      IPACKAGES="$@"
    fi

    for IPACKAGE in $IPACKAGES; do
      if echo "$IGNORED_PACKAGES" | grep -Eq '(^| +)'$IPACKAGE'( +|$)'; then
        echoerr "Package '$IPACKAGE' already ignored."
      elif ! echo "$LIVE_PACKAGES" | grep -Eq '(^| +)'$IPACKAGE'( +|$)'; then
        echoerr "No such package '$IPACKAGE' in dependencies."
      else
        if [[ -z "$IGNORED_PACKAGES" ]]; then
          PACKAGE=`echo "$PACKAGE" | jq 'setpath(["catalyst","version-check","ignore"]; ["'$IPACKAGE'"])'`
        else
          PACKAGE=`echo "$PACKAGE" | jq 'setpath(["catalyst","version-check","ignore"]; getpath(["catalyst","version-check","ignore"]) + ["'$IPACKAGE'"])'`
        fi
        IGNORED_PACKAGES="${IGNORED_PACKAGES} ${IPACKAGE}"
      fi
    done
  elif [[ -n "$UNIGNORE" ]]; then
    if [[ -z "$IGNORED_PACKAGES" ]]; then
      if (( $# > 0 )); then
        echoerr "No packages currently ignored."
      else
        echo "No packages currently ignored."
      fi
      exit
    fi
    if (( $# == 0 )); then # interactive add
      PS3="Include package: "
      selectDoneCancelAll IPACKAGES $IGNORED_PACKAGES
    else
      IPACKAGES="$@"
    fi

    for IPACKAGE in $IPACKAGES; do
      if ! echo "$IGNORED_PACKAGES" | grep -Eq '(^| +)'$IPACKAGE'( +|$)'; then
        echoerr "Package '$IPACKAGE' is not currently ignored."
      else
        PACKAGE=`echo "$PACKAGE" | jq 'setpath(["catalyst","version-check","ignore"]; getpath(["catalyst","version-check","ignore"]) | map(select(. != "'$IPACKAGE'")))'`
      fi
    done
  fi

  # TODO: cleanup empty bits
  echo "$PACKAGE" > "$PACKAGE_FILE"

  if [[ -n "$SHOW_CONFIG" ]]; then
    project-packages-version-check -c
  fi
}

packagesVersionCheckShowConfig() {
  if [[ -z "$IGNORED_PACKAGES" ]]; then
    echo "Ignored packages: none"
  else
    echo "Ignored packages:"
    echo "$IGNORED_PACKAGES" | tr " " "\n" | sed -E 's/^/  /'
  fi
  if [[ -z "$CMD_OPTS" ]]; then
    echo "Additional options: none"
  else
    echo "Additional options: $CMD_OPTS"
  fi
}

packagesVersionCheckSetOptions() {
  if [[ -n "$OPTIONS" ]]; then
    PACKAGE=$(echo "$PACKAGE" | jq 'setpath(["catalyst","version-check","options"]; "'$OPTIONS'")')
  elif [[ -z "$OPTIONS" ]]; then
    PACKAGE=$(echo "$PACKAGE" | jq 'del(.catalyst."version-check".options)')
  fi
  echo "$PACKAGE" > "$PACKAGE_FILE"
}

packagesVersionCheck() {
  for IPACKAGE in $IGNORED_PACKAGES; do
    CMD_OPTS="${CMD_OPTS} -i ${IPACKAGE}"
  done
  if [[ -n "$UPDATE" ]]; then
    CMD_OPTS="${CMD_OPTS} -u"
  fi
  npm-check ${CMD_OPTS} || true
}

packages-find-package() {
  local FILE_VAR="${1}"; shift
  local NAME_VAR="${1}"; shift
  local LINK_SPEC="${1}"; shift

  local LINK_PROJECT=$(echo "$LINK_SPEC" | awk -F: '{print $1}')
  local LINK_PACKAGE=$(echo "$LINK_SPEC" | awk -F: '{print $2}')

  if [[ ! -d "${CATALYST_PLAYGROUND}/${LINK_PROJECT}" ]]; then
    echoerrandexit "Could not find project directory '${LINK_PROJECT}' in Catalyst playground."
  fi

  local CANDIDATE_PACKAGE_FILE=''
  local CANDIDATE_PACKAGE_NAME=''
  local CANDIDATE_PACKAGE_FILE=''
  local CANDIDATE_PACKAGE_FILE_IT=''
  local CANDIDATE_COUNT=0
  while read CANDIDATE_PACKAGE_FILE_IT; do
    # Not sure why, but the _IT is necessary because setting
    # CANDIDATE_PACKAGE_FILE directly in the read causes the value to reset
    # after the loop.
    CANDIDATE_PACKAGE_FILE="${CANDIDATE_PACKAGE_FILE_IT}"
    CANDIDATE_PACKAGE_NAME=$(cat "$CANDIDATE_PACKAGE_FILE" | jq --raw-output '.name | @sh' | tr -d "'")
    if [[ -n "$LINK_PACKAGE" ]]; then
      if [[ "$LINK_PACKAGE" == "$CANDIDATE_PACKAGE_NAME" ]]; then
        break;
      fi
    elif (( $CANDIDATE_COUNT > 0 )); then
      echoerrandexit "Project '$LINK_PROJECT' contains multiple packages. You must specify the package. Try\ncatalyst packages link $(test ! -n "$UNLINK" || echo "--unlink " )${LINK_PROJECT}:<package name>"
    fi
    CANDIDATE_COUNT=$(( $CANDIDATE_COUNT + 1 ))
  done < <(find -H "${CATALYST_PLAYGROUND}/${LINK_PROJECT}" -name "package.json" -not -path "*/node_modules*/*")

  # If we get here without exiting, then 'CANDIDATE_PACKAGE_FILE' has the
  # location of the package.json we want to link.
  eval "${FILE_VAR}='${CANDIDATE_PACKAGE_FILE}'; ${NAME_VAR}='${CANDIDATE_PACKAGE_NAME}'"
}

packages-link-dolink() {
  local INSTALLED_PACKAGE_DIR="$1"
  local LINK_PACKAGE_DIR="$2"

  if [[ -e "$INSTALLED_PACKAGE_DIR" ]]; then
    mv "$INSTALLED_PACKAGE_DIR" "${INSTALLED_PACKAGE_DIR}.prelink"
  fi
  mkdir "$INSTALLED_PACKAGE_DIR"
  # TODO: we were experiencing problems where the file viewed from the link would not always update, so we're trying turning off "unified buffer cache" to see if that fixes the problem.
  bindfs --perms=a-w -o noubc "$LINK_PACKAGE_DIR" "$INSTALLED_PACKAGE_DIR"

  local LINK_PACKAGE_NAME=$(basename "$LINK_PACKAGE_DIR")
  local CURR_PROJECT=$(basename "$BASE_DIR")
  echo "Linked '${LINK_PACKAGE_NAME}' to '$CURR_PROJECT'."
}

packagesUnlink() {
  # TODO: possible bug? Maybe when it is catalyst-scripts itself which is linked, this hangs because the script itself causes the mount to be busy
  local INSTALLED_PACKAGE_DIR="$1"
  local LINK_PACKAGE_DIR="$2"

  # These two used in user output.
  local LINK_PACKAGE_NAME=$(basename "$LINK_PACKAGE_DIR")
  local CURR_PROJECT=$(basename "$BASE_DIR")

  if mount | grep -q "$INSTALLED_PACKAGE_DIR"; then
    umount "$INSTALLED_PACKAGE_DIR"
    if [[ -e "${INSTALLED_PACKAGE_DIR}.prelink" ]]; then
      mv "${INSTALLED_PACKAGE_DIR}.prelink" "${INSTALLED_PACKAGE_DIR}"
    else
      echowarn "No previous installation for '${LINK_PACKAGE_NAME}' was found to restore. You might want to (re-)install the package."
    fi
    echo "Package '${LINK_PACKAGE_NAME}' unlinked from '$CURR_PROJECT'."
  else
    echoerr "'${LINK_PACKAGE_NAME}' does not appear to be linked to '$CURR_PROJECT'. Perhaps the projects are npm-linked rather than Catalyst linked? You can also try unlinking everything with:\ncatalyst link --unlink ${CURR_PROJECT}"
  fi
}

packagesUnlinkAll() {
  local PACKAGE_PATH="$1"

  local MOUNT_SPEC
  while read MOUNT_SPEC; do
    # TODO: a pathname with ' on ' will mess this up. Unfortunately, mount does
    # not have a clean/safe/scriptable output option.
    local MOUNT_SRC=$(echo "$MOUNT_SPEC" | sed -Ee 's| on .+||')
    local MOUNT_POINT=$(echo "$MOUNT_SPEC" | sed -Ee 's|.+ on (/.+) \(.+|\1|')
    packagesUnlink "$MOUNT_POINT" "$MOUNT_SRC"
  done < <(mount | grep -s "$PACKAGE_PATH/node_modules" || echowarn "Did not find any linked packages in '$(basename "$PACKAGE_PATH")'.")
}

packages-link-list() {
  local PACKAGE_PATH=${1:-$BASE_DIR}
  # It's been observed that links can break and the mountpoint become
  # un-mounted. So, we search for 'prelink' markers.
  local NPM_ROOT="$(cd "${PACKAGE_PATH}" && npm root)"
  # Notice because of crazy bash quote don't quote 's|...|'
  local TFORMER="sed -Ee s|(/[^@]*)?/(@[^/]+/)?([^/]+).prelink|\2\3|"
  local LINKED_PACKAGES=$(find "$NPM_ROOT"/\@* -maxdepth 1 -type d -name "*.prelink" \
    | $TFORMER)
  # TODO: once we have 'list-add-all', use that here
  local ANOTHER
  for ANOTHER in $(find "$NPM_ROOT" -maxdepth 1 -type d -name "*.prelink" | $TFORMER); do
    list-add-item LINKED_PACKAGES "$ANOTHER"
  done
  echo "$LINKED_PACKAGES"
  # For reference, the following will find links by mountpint:
  # mount | grep -s "$PACKAGE_PATH/node_modules" | sed -Ee 's|.+ on (/[^@]*)?/(\@[^/]+/)?([^/]+) \(.+|\2\3|'
}
