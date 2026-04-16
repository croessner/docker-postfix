#!/bin/sh
set -eu

log() {
  printf '%s %s\n' '[postfix-entrypoint]' "$*"
}

warn() {
  printf '%s %s\n' '[postfix-entrypoint][warn]' "$*" >&2
}

die() {
  printf '%s %s\n' '[postfix-entrypoint][error]' "$*" >&2
  exit 1
}

bool_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

file_env() {
  var="$1"
  default="${2:-}"
  file_var="${var}_FILE"

  eval "var_value=\${$var:-}"
  eval "file_value=\${$file_var:-}"

  if [ -n "${var_value}" ] && [ -n "${file_value}" ]; then
    die "Both ${var} and ${file_var} are set. Please use only one."
  fi

  if [ -n "${file_value}" ]; then
    [ -r "${file_value}" ] || die "Cannot read ${file_var} path: ${file_value}"
    var_value="$(cat "${file_value}")"
  fi

  if [ -z "${var_value}" ]; then
    var_value="${default}"
  fi

  export "${var}=${var_value}"
  unset "${file_var}" || true
}

append_sorted_dir() {
  dir="$1"
  pattern="$2"

  if [ ! -d "$dir" ]; then
    return 0
  fi

  for file in "$dir"/$pattern; do
    [ -e "$file" ] || continue
    printf '\n# --- begin %s ---\n' "$file" >> "$3"
    cat "$file" >> "$3"
    printf '\n# --- end %s ---\n' "$file" >> "$3"
  done
}

list_prefixed_vars() {
  prefix="$1"
  reserved="$2"

  env | cut -d= -f1 | sort -u | while IFS= read -r name; do
    case "$name" in
      "${prefix}"*)
        skip=0
        for item in $reserved; do
          case "$name" in
            ${item}) skip=1 ;;
          esac
        done
        [ "$skip" -eq 1 ] && continue
        case "$name" in
          *_FILE) printf '%s\n' "${name%_FILE}" ;;
          *) printf '%s\n' "$name" ;;
        esac
        ;;
    esac
  done | sort -u
}

ensure_dir() {
  dir="$1"
  owner="$2"
  group="$3"
  mode="$4"

  mkdir -p "$dir"
  chown "$owner:$group" "$dir"
  chmod "$mode" "$dir"
}

derive_domain_from_hostname() {
  host="$1"
  case "$host" in
    *.*) printf '%s' "${host#*.}" ;;
    *) printf '%s' 'localdomain' ;;
  esac
}

decode_master_selector() {
  printf '%s' "$1" \
    | sed -e 's/___/-/g' -e 's/__/\//g'
}

copy_base_configs() {
  main_source="/usr/share/postfix/default-config/container-main.cf"
  dynamicmaps_source="/usr/share/postfix/default-config/dynamicmaps.cf"
  master_source="/usr/share/postfix/default-config/container-master.cf"
  HAS_CUSTOM_MAIN=0

  if [ -f /etc/postfix/custom-config/main.cf ]; then
    main_source=/etc/postfix/custom-config/main.cf
    HAS_CUSTOM_MAIN=1
  fi
  if [ -f /etc/postfix/custom-config/dynamicmaps.cf ]; then
    dynamicmaps_source=/etc/postfix/custom-config/dynamicmaps.cf
  fi
  if [ -f /etc/postfix/custom-config/master.cf ]; then
    master_source=/etc/postfix/custom-config/master.cf
  fi

  cp "$main_source" /etc/postfix/main.cf
  cp "$master_source" /etc/postfix/master.cf

  if [ -f "${dynamicmaps_source}" ]; then
    cp "${dynamicmaps_source}" /etc/postfix/dynamicmaps.cf
  fi

  append_sorted_dir /etc/postfix/custom-config/main.cf.d '*.cf' /etc/postfix/main.cf
  if [ -f /etc/postfix/dynamicmaps.cf ]; then
    append_sorted_dir /etc/postfix/custom-config/dynamicmaps.cf.d '*.cf' /etc/postfix/dynamicmaps.cf
  fi
  append_sorted_dir /etc/postfix/custom-config/master.cf.d '*.cf' /etc/postfix/master.cf
}

apply_runtime_defaults() {
  file_env POSTFIX_RUNTIME_LOG_TO_STDOUT true
  file_env POSTFIX_RUNTIME_HOSTNAME ''
  file_env POSTFIX_RUNTIME_DOMAIN ''
  file_env POSTFIX_RUNTIME_DESTINATIONS ''
  file_env POSTFIX_RUNTIME_MYNETWORKS '127.0.0.0/8 [::1]/128'
  file_env POSTFIX_RUNTIME_POSTMAPS ''
  file_env POSTFIX_RUNTIME_RUN_SCRIPTS true
  file_env POSTFIX_RUNTIME_AUTO_POSTMAP_STANDARD true
  file_env POSTFIX_RUNTIME_TLSRPT_SOCKET_NAME 'run/tlsrpt/tlsrpt.sock'

  runtime_hostname="${POSTFIX_RUNTIME_HOSTNAME}"
  if [ -z "${runtime_hostname}" ]; then
    runtime_hostname="$(hostname -f 2>/dev/null || hostname)"
  fi

  runtime_domain="${POSTFIX_RUNTIME_DOMAIN}"
  if [ -z "${runtime_domain}" ]; then
    runtime_domain="$(derive_domain_from_hostname "${runtime_hostname}")"
  fi

  runtime_destinations="${POSTFIX_RUNTIME_DESTINATIONS}"
  if [ -z "${runtime_destinations}" ]; then
    runtime_destinations="${runtime_hostname}, localhost.${runtime_domain}, localhost"
  fi

  postconf -c /etc/postfix -e "compatibility_level = 3.11"
  postconf -c /etc/postfix -e "queue_directory = /var/spool/postfix"
  postconf -c /etc/postfix -e "command_directory = /usr/sbin"
  postconf -c /etc/postfix -e "daemon_directory = /usr/libexec/postfix"
  postconf -c /etc/postfix -e "data_directory = /var/lib/postfix"
  postconf -c /etc/postfix -e "meta_directory = /etc/postfix"
  postconf -c /etc/postfix -e "shlib_directory = /usr/lib/postfix"
  postconf -c /etc/postfix -e "mail_owner = postfix"
  postconf -c /etc/postfix -e "setgid_group = postdrop"
  postconf -c /etc/postfix -e 'readme_directory = no'
  postconf -c /etc/postfix -e 'html_directory = no'

  if [ "${HAS_CUSTOM_MAIN}" -ne 1 ]; then
    postconf -c /etc/postfix -e "myhostname = ${runtime_hostname}"
    postconf -c /etc/postfix -e "mydomain = ${runtime_domain}"
    postconf -c /etc/postfix -e "myorigin = \$myhostname"
    postconf -c /etc/postfix -e "mydestination = ${runtime_destinations}"
    postconf -c /etc/postfix -e "mynetworks = ${POSTFIX_RUNTIME_MYNETWORKS}"
    postconf -c /etc/postfix -e 'inet_interfaces = all'
    postconf -c /etc/postfix -e 'inet_protocols = all'
    postconf -c /etc/postfix -e 'biff = no'
    postconf -c /etc/postfix -e 'append_dot_mydomain = no'
    postconf -c /etc/postfix -e 'smtpd_banner = $myhostname ESMTP $mail_name'
    postconf -c /etc/postfix -e 'default_database_type = lmdb'
    postconf -c /etc/postfix -e 'smtp_tls_security_level = may'
    postconf -c /etc/postfix -e 'smtpd_tls_security_level = may'
    postconf -c /etc/postfix -e 'tls_preempt_cipherlist = yes'
    postconf -c /etc/postfix -e 'smtp_tlsrpt_enable = no'
    postconf -c /etc/postfix -e "smtp_tlsrpt_socket_name = ${POSTFIX_RUNTIME_TLSRPT_SOCKET_NAME}"

    if bool_true "${POSTFIX_RUNTIME_LOG_TO_STDOUT}"; then
      postconf -c /etc/postfix -e 'maillog_file = /dev/stdout'
      postconf -c /etc/postfix -e 'maillog_file_permissions = 0644'
    else
      postconf -c /etc/postfix -X maillog_file || true
      postconf -c /etc/postfix -X maillog_file_permissions || true
    fi
  fi
}

apply_main_overrides() {
  list_prefixed_vars POSTFIX_ 'POSTFIX_RUNTIME_* POSTFIXMASTER_*' | while IFS= read -r name; do
    [ -n "$name" ] || continue
    file_env "$name"
    param="${name#POSTFIX_}"
    eval "value=\${$name}"
    postconf -c /etc/postfix -e "${param} = ${value}"
    log "Applied main.cf override: ${param}"
  done
}

apply_master_overrides() {
  list_prefixed_vars POSTFIXMASTER_ '' | while IFS= read -r name; do
    [ -n "$name" ] || continue
    file_env "$name"
    selector="$(decode_master_selector "${name#POSTFIXMASTER_}")"
    eval "value=\${$name}"
    postconf -c /etc/postfix -P "${selector}=${value}"
    log "Applied master.cf override: ${selector}"
  done
}

run_entrypoint_scripts() {
  if ! bool_true "${POSTFIX_RUNTIME_RUN_SCRIPTS}"; then
    return 0
  fi

  if [ ! -d /docker-entrypoint-init.d ]; then
    return 0
  fi

  for file in /docker-entrypoint-init.d/*; do
    [ -e "$file" ] || continue
    case "$file" in
      *.sh)
        if [ -x "$file" ]; then
          log "Running init script $file"
          "$file"
        else
          log "Sourcing init script $file"
          . "$file"
        fi
        ;;
      *)
        warn "Ignoring unsupported init artifact: $file"
        ;;
    esac
  done
}

compile_standard_maps() {
  if ! bool_true "${POSTFIX_RUNTIME_AUTO_POSTMAP_STANDARD}"; then
    return 0
  fi

  for map in /etc/aliases /etc/postfix/access /etc/postfix/canonical /etc/postfix/generic /etc/postfix/relocated /etc/postfix/transport /etc/postfix/virtual; do
    [ -f "$map" ] || continue
    if [ -s "$map" ]; then
      log "Compiling standard map $map"
      postmap -c /etc/postfix "$map"
    fi
  done

  if [ -f /etc/aliases ] && [ -s /etc/aliases ]; then
    log 'Running newaliases'
    newaliases
  fi
}

compile_declared_maps() {
  [ -n "${POSTFIX_RUNTIME_POSTMAPS}" ] || return 0

  OLD_IFS="$IFS"
  IFS=','
  set -- ${POSTFIX_RUNTIME_POSTMAPS}
  IFS="$OLD_IFS"

  for spec in "$@"; do
    spec="$(printf '%s' "$spec" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$spec" ] || continue
    log "Compiling declared map ${spec}"
    postmap -c /etc/postfix "${spec}"
  done
}

prepare_runtime() {
  ensure_dir /var/lib/postfix postfix postfix 0755
  ensure_dir /var/spool/postfix root root 0755
  ensure_dir /var/spool/postfix/pid root root 0755
  ensure_dir /var/spool/postfix/public postfix postdrop 02710
  ensure_dir /var/spool/postfix/maildrop root postdrop 1730
  ensure_dir /var/spool/postfix/run root root 0755
  ensure_dir /var/spool/postfix/etc root root 0755
  ensure_dir /var/spool/postfix/usr/lib/postfix root root 0755
  ensure_dir /var/spool/postfix/usr/lib root root 0755
  ensure_dir /var/spool/postfix/usr root root 0755
  ensure_dir /var/spool/postfix/lib root root 0755
  ensure_dir /var/spool/postfix/dev root root 0755
  if [ ! -d /etc/postfix/maps ]; then
    mkdir -p /etc/postfix/maps
  fi
}

configure_postfix() {
  prepare_runtime
  copy_base_configs
  apply_runtime_defaults
  apply_main_overrides
  apply_master_overrides
  run_entrypoint_scripts
  compile_standard_maps
  compile_declared_maps
  postfix set-permissions || true
  postfix check
}

main() {
  if [ "$#" -eq 0 ]; then
    set -- postfix start-fg
  fi

  if [ "${1#-}" != "$1" ]; then
    set -- postfix "$@"
  fi

  case "$1" in
    postfix)
      if [ "${2:-}" = "start-fg" ] || [ "${2:-}" = "start" ] || [ "${2:-}" = "check" ] || [ "${2:-}" = "reload" ]; then
        configure_postfix
      fi
      exec "$@"
      ;;
    *)
      exec "$@"
      ;;
  esac
}

main "$@"
