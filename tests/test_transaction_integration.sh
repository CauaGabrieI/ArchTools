#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

STATE_DIR="$state/arch-smart-postinstall"
RUN_ID=run-integration-test
DRY_RUN=0
LOG_FILE=''
PLAN_PACKAGES=()
source "$root/lib/transaction.sh"
source "$root/lib/packages.sh"
source "$root/lib/executor.sh"

declare -A installed=([already]=1) available=([missing]=0 [good]=1 [already]=1 [fail]=1 [plain]=1)
is_package_installed() { [[ ${installed[$1]:-0} == 1 ]]; }
package_available() { [[ ${available[$1]:-0} == 1 ]]; }
sudo() { [[ ${SUDO_FAIL:-0} == 0 ]]; }
source "$root/lib/logger.sh"
source "$root/lib/state.sh"
init_state

begin_transaction packages
is_package_installed() { [[ ${installed[$1]:-0} == 1 ]]; }
sudo() {
  if [[ ${SUDO_FAIL:-0} == 1 ]]; then return 1; fi
  if [[ ${1:-} == systemctl && ${2:-} == enable ]]; then SERVICE_ENABLED_NEW=enabled; fi
  installed[good]=1
  return 0
}
install_packages good
grep -q $'\tchange\tpackage\tgood\tabsent\tinstalled\tyes$' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
commit_transaction

begin_transaction packages
install_packages already
! grep -q $'\tchange\tpackage\talready\t' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
  if install_packages missing; then exit 1; fi
! grep -q $'\tchange\tpackage\tmissing\t' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
  abort_transaction "pacote indisponível"

begin_transaction packages
SUDO_FAIL=1
installed[fail]=0
if install_packages fail; then exit 1; fi
! grep -q $'\tchange\tpackage\tfail\t' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
SUDO_FAIL=0
abort_transaction "falha"

SERVICE_ENABLED_NEW=disabled
systemctl() {
  case "$1" in
    is-enabled)
      if [[ $2 == enabled.service || ${SERVICE_ENABLED_NEW} == enabled ]]; then
        printf 'enabled\n'
        return 0
      fi
      printf 'disabled\n'
      return 1
      ;;
    *) return 0 ;;
  esac
}

begin_transaction services
enable_service_safe new.service
grep -q $'\tchange\tservice\tnew.service\tdisabled\tenabled\tyes$' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
commit_transaction

begin_transaction services
enable_service_safe enabled.service
! grep -q $'\tchange\tservice\tenabled.service\t' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
abort_transaction "sem alterações"

begin_transaction services
systemctl() {
  case "$1" in
    is-enabled) [[ ${service_state[$2]:-disabled} == enabled ]] ;;
    *) return 1 ;;
  esac
}
if enable_service_safe failed.service; then exit 1; fi
! grep -q $'\tchange\tservice\tfailed.service\t' "$STATE_DIR/transactions/$TRANSACTION_ID.tsv"
abort_transaction "falha"

TRANSACTION_ID=''; TRANSACTION_STATUS=''
installed[plain]=0
sudo() { installed[plain]=1; return 0; }
install_packages plain
[[ ! -e "$state/arch-smart-postinstall/transactions.tsv" ]] || ! grep -q $'\tchange\tpackage\tplain\t' "$state/arch-smart-postinstall/transactions/"*.tsv
echo 'test_transaction_integration: ok'
