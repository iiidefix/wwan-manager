# wwan-manager settings, sourced by the commands.
# load_config VAR=DEFAULT... sets each VAR. Lowest to highest preference:
# the default given here, /etc/default/wwan-manager, the environment
# (e.g. "IPV6=yes ifup wwan0"; an empty value in the environment counts).
load_config() {
	local a v fromenv=()
	for a in "$@"; do
		v=${a%%=*}
		[ -n "${!v+x}" ] && fromenv+=("$v=${!v}")
		printf -v "$v" %s "${a#*=}"
	done
	[ -r /etc/default/wwan-manager ] && . /etc/default/wwan-manager
	for a in "${fromenv[@]}"; do
		printf -v "${a%%=*}" %s "${a#*=}"
	done
	return 0
}
