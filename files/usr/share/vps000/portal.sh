# Portal API — aligned with VPS000 clients (www.vps000.org).
# Sourced by /usr/sbin/vps000. Do not execute directly.

PORTAL_BASE=https://www.vps000.org
PORTAL_UA="VPS000Router/1.3.0"
ACC_CACHE=/tmp/vps000.account
PROD_CACHE=/tmp/vps000.products
ACC_TS=/tmp/vps000.account.ts
PORTAL_JAR="$STATE_DIR/portal.cj"
ORDER_CACHE=/tmp/vps000.order
PORTAL_TRIES=3

portal_curl() {
	curl -4 -sS -k -L -m 12 --connect-timeout 6 -A "$PORTAL_UA" "$@"
}

portal_fetch() {
	local n=0 body code
	while [ "$n" -lt "$PORTAL_TRIES" ]; do
		body=$(portal_curl "$@")
		code=$(portal_jf "$body" '@.code')
		if [ "$code" = "200" ]; then
			printf '%s' "$body"
			return 0
		fi
		n=$((n + 1))
		[ "$n" -lt "$PORTAL_TRIES" ] && sleep 1
	done
	return 1
}

portal_jf() {
	jsonfilter -s "$1" -e "$2" 2>/dev/null
}

portal_pin() {
	pin_host_via_wan www.vps000.org "$(cat "$STATE_DIR/wan_gw" 2>/dev/null)"
}

plan_name_of() {
	case "$1" in
		0|2) printf '%s' "账户已到期" ;;
		3) printf '%s' "免费体验" ;;
		1|4|5) printf '%s' "个人会员" ;;
		6|7|8|9) printf '%s' "4K/VR" ;;
		*) printf '套餐%s' "$1" ;;
	esac
}

is_unopened_vip() {
	case "$1" in
		0|2) return 0 ;;
	esac
	return 1
}

is_fourk_vip() {
	case "$1" in
		6|7|8|9) return 0 ;;
	esac
	return 1
}

end_time_expired() {
	local end now
	end="$1"
	[ -n "$end" ] || return 0
	now=$(date '+%Y-%m-%d %H:%M:%S')
	[ "$end" \< "$now" ]
}

product_allowed() {
	local id vip expired
	id="$1"
	vip="$2"
	expired="$3"
	case "$id" in
		1|2|3|4|5|6|7|8|9|10|2511) ;;
		*) return 1 ;;
	esac
	if [ "$expired" = "1" ] || is_unopened_vip "$vip"; then
		return 0
	fi
	if is_fourk_vip "$vip"; then
		case "$id" in
			6|7|8|9) return 0 ;;
		esac
		return 1
	fi
	case "$id" in
		1|3|4|5|10) return 0 ;;
	esac
	return 1
}

save_account_cache() {
	local id username email vip end plan expired
	id="$1"; username="$2"; email="$3"; vip="$4"; end="$5"
	expired=0
	end_time_expired "$end" && expired=1
	plan=$(plan_name_of "$vip")
	mkdir_state
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$username" "$email" "$vip" "$end" "$plan" "$expired" > "$ACC_CACHE"
	date +%s > "$ACC_TS"
}

migrate_account_cache() {
	[ -s "$ACC_CACHE" ] && return 0
	[ -s "$STATE_DIR/account.cache" ] || return 0
	cp "$STATE_DIR/account.cache" "$ACC_CACHE" 2>/dev/null || true
	[ -s "$STATE_DIR/account.ts" ] && cp "$STATE_DIR/account.ts" "$ACC_TS" 2>/dev/null || true
}

read_account_field() {
	migrate_account_cache
	[ -s "$ACC_CACHE" ] || return 1
	awk -F '\t' -v n="$1" 'NF{print $n; exit}' "$ACC_CACHE"
}

account_id() { read_account_field 1; }
account_end() { read_account_field 5; }
account_plan() { read_account_field 6; }
account_expired() { read_account_field 7; }
account_vip() { read_account_field 4; }

fetch_userinfo() {
	local user pass body id username email vip end
	portal_pin
	user=$(uci_get account)
	pass=$(uci_get password)
	[ -n "$user" ] && [ -n "$pass" ] || return 1
	body=$(portal_fetch -X POST \
		--data-urlencode "username=$user" \
		--data-urlencode "password=$pass" \
		"$PORTAL_BASE/api/userinfo") || return 1
	id=$(portal_jf "$body" '@.data.id')
	username=$(portal_jf "$body" '@.data.username')
	email=$(portal_jf "$body" '@.data.email')
	vip=$(portal_jf "$body" '@.data.vip_type')
	end=$(portal_jf "$body" '@.data.end_time')
	[ -n "$id" ] || return 1
	save_account_cache "$id" "$username" "$email" "$vip" "$end"
	return 0
}

fetch_products() {
	local body
	portal_pin
	body=$(portal_fetch "$PORTAL_BASE/api/products") || return 1
	printf '%s\n' "$body" > "$PROD_CACHE"
	return 0
}

products_json_for_user() {
	local vip expired i id name ap pp first prod
	vip=$(account_vip)
	expired=$(account_expired)
	[ -n "$vip" ] || vip=2
	[ -n "$expired" ] || expired=1
	[ -s "$PROD_CACHE" ] || fetch_products || {
		printf '[]'
		return 1
	}
	prod=$(cat "$PROD_CACHE")
	first=1
	printf '['
	i=0
	while [ "$i" -lt 40 ]; do
		id=$(jsonfilter -s "$prod" -e "@.data[$i].id" 2>/dev/null)
		[ -n "$id" ] || break
		if product_allowed "$id" "$vip" "$expired"; then
			name=$(jsonfilter -s "$prod" -e "@.data[$i].name" 2>/dev/null)
			ap=$(jsonfilter -s "$prod" -e "@.data[$i].alipay_price" 2>/dev/null)
			pp=$(jsonfilter -s "$prod" -e "@.data[$i].paypal_price" 2>/dev/null)
			[ "$first" = 1 ] || printf ','
			first=0
			printf '{"id":%s,"name":"%s","alipay":"%s","paypal":"%s"}' \
				"$id" "$(json_escape "$name")" "$(json_escape "$ap")" "$(json_escape "$pp")"
		fi
		i=$((i + 1))
	done
	printf ']'
}

cmd_account() {
	local id username email vip end plan expired stale
	mkdir_state
	migrate_account_cache
	stale=0
	if fetch_userinfo; then
		fetch_products >/dev/null 2>&1 || true
	else
		stale=1
		[ -s "$ACC_CACHE" ] || {
			json_out '{"ok":false,"msg":"账户信息暂未获取"}'
			return 1
		}
	fi
	id=$(account_id)
	username=$(read_account_field 2)
	email=$(read_account_field 3)
	vip=$(account_vip)
	end=$(account_end)
	plan=$(account_plan)
	expired=$(account_expired)
	json_out "{\"ok\":true,\"stale\":\"$stale\",\"user_id\":\"$(json_escape "$id")\",\"username\":\"$(json_escape "$username")\",\"email\":\"$(json_escape "$email")\",\"vip_type\":\"$(json_escape "$vip")\",\"end_time\":\"$(json_escape "$end")\",\"plan\":\"$(json_escape "$plan")\",\"expired\":\"$(json_escape "$expired")\",\"products\":$(products_json_for_user)}"
}

maybe_refresh_account() {
	local age
	[ -n "$(uci_get account)" ] || return 0
	migrate_account_cache
	if [ -s "$ACC_CACHE" ] && [ -s "$ACC_TS" ]; then
		age=$(($(date +%s) - $(cat "$ACC_TS")))
		[ "$age" -lt 600 ] 2>/dev/null && return 0
	fi
	[ -f "$STATE_DIR/account.job" ] && kill -0 "$(cat "$STATE_DIR/account.job" 2>/dev/null)" 2>/dev/null && return 0
	mkdir_state
	(
		echo $$ > "$STATE_DIR/account.job"
		fetch_userinfo >/dev/null 2>&1 || true
		[ -s "$PROD_CACHE" ] || fetch_products >/dev/null 2>&1 || true
		rm -f "$STATE_DIR/account.job"
	) >/dev/null 2>&1 &
}

cmd_order() {
	local uid pid pay month body code ono url
	uid=$(account_id)
	[ -n "$uid" ] || fetch_userinfo >/dev/null 2>&1 || true
	uid=$(account_id)
	pid=$(scrub "$1")
	pay=$(scrub "$2")
	month=$(scrub "$3")
	[ -n "$month" ] || month=1
	case "$pid" in
		[0-9]*) ;;
		*) json_out '{"ok":false,"msg":"请选择套餐"}'; return 1 ;;
	esac
	case "$pay" in
		1|2) ;;
		*) json_out '{"ok":false,"msg":"支付方式无效"}'; return 1 ;;
	esac
	case "$month" in
		1|3|6|12) ;;
		*) month=1 ;;
	esac
	[ -n "$uid" ] || {
		json_out '{"ok":false,"msg":"请先刷新账户"}'
		return 1
	}
	product_allowed "$pid" "$(account_vip)" "$(account_expired)" || {
		json_out '{"ok":false,"msg":"当前套餐期内只能续同档"}'
		return 1
	}
	portal_pin
	body=$(portal_curl -X POST \
		--data-urlencode "user_id=$uid" \
		--data-urlencode "product_id=$pid" \
		--data-urlencode "month=$month" \
		--data-urlencode "pay_type=$pay" \
		"$PORTAL_BASE/api/order")
	code=$(portal_jf "$body" '@.code')
	if [ "$code" != "200" ]; then
		json_out "{\"ok\":false,\"msg\":\"$(json_escape "$(portal_jf "$body" '@.msg')")\"}"
		return 1
	fi
	ono=$(portal_jf "$body" '@.data.order_no')
	url=$(portal_jf "$body" '@.data.pay_url')
	if [ -z "$ono" ] || [ -z "$url" ]; then
		json_out '{"ok":false,"msg":"订单缺少支付链接"}'
		return 1
	fi
	printf '%s\t%s\t%s\n' "$uid" "$ono" "$url" > "$ORDER_CACHE"
	json_out "{\"ok\":true,\"order_no\":\"$(json_escape "$ono")\",\"pay_url\":\"$(json_escape "$url")\",\"pay_type\":\"$pay\"}"
}

cmd_order_status() {
	local uid ono body code st
	uid=$(account_id)
	ono=$(scrub "$1")
	[ -n "$ono" ] || ono=$(awk -F '\t' 'NF{print $2; exit}' "$ORDER_CACHE" 2>/dev/null)
	[ -n "$uid" ] && [ -n "$ono" ] || {
		json_out '{"ok":false,"msg":"没有待查询订单"}'
		return 1
	}
	portal_pin
	body=$(portal_curl "$PORTAL_BASE/api/order-status?user_id=$(printf '%s' "$uid" | sed 's/ /%20/g')&order_no=$(printf '%s' "$ono" | sed 's/ /%20/g')")
	code=$(portal_jf "$body" '@.code')
	if [ "$code" != "200" ]; then
		json_out "{\"ok\":false,\"msg\":\"$(json_escape "$(portal_jf "$body" '@.msg')")\"}"
		return 1
	fi
	st=$(portal_jf "$body" '@.data.pay_status')
	json_out "{\"ok\":true,\"order_no\":\"$(json_escape "$ono")\",\"pay_status\":\"$(json_escape "$st")\"}"
}

portal_extract_csrf() {
	printf '%s' "$1" | sed -n 's/.*name=["'"'"']_csrf-max["'"'"'][^>]*value=["'"'"']\([^"'"'"']*\)["'"'"'].*/\1/p' | head -1
}

cmd_logoff() {
	local user pass html csrf posted hdr
	user=$(uci_get account)
	pass=$(uci_get password)
	[ -n "$user" ] && [ -n "$pass" ] || {
		json_out '{"ok":false,"msg":"请先填写账号密码"}'
		return 1
	}
	portal_pin
	mkdir_state
	rm -f "$PORTAL_JAR"
	html=$(portal_curl -c "$PORTAL_JAR" -b "$PORTAL_JAR" "$PORTAL_BASE/site/login")
	csrf=$(portal_extract_csrf "$html")
	posted=$(portal_curl -c "$PORTAL_JAR" -b "$PORTAL_JAR" -D "$STATE_DIR/portal.hdr" \
		-e "$PORTAL_BASE/site/login" \
		--data-urlencode "r=/site/login" \
		--data-urlencode "username=$user" \
		--data-urlencode "password=$pass" \
		${csrf:+--data-urlencode "_csrf-max=$csrf"} \
		"$PORTAL_BASE/site/login")
	hdr=$(cat "$STATE_DIR/portal.hdr" 2>/dev/null)
	if ! printf '%s\n%s\n' "$hdr" "$posted" | grep -qE '/user/logoff|/user($|[^a-z])'; then
		if printf '%s' "$posted" | grep -qi 'name="password"' && \
		   printf '%s' "$posted" | grep -qi 'name="username"'; then
			json_out '{"ok":false,"msg":"门户登录失败，无法下线其他设备"}'
			rm -f "$PORTAL_JAR"
			return 1
		fi
	fi
	portal_curl -c "$PORTAL_JAR" -b "$PORTAL_JAR" "$PORTAL_BASE/user/logoff" >/dev/null 2>&1 || true
	rm -f "$PORTAL_JAR"
	log "portal logoff requested"
	if wanted; then
		(
			sleep 2
			KEEP_WANT=1 /usr/sbin/vps000 disconnect >/dev/null 2>&1 || true
			/usr/sbin/vps000 connect replace >/dev/null 2>&1 || true
		) >/dev/null 2>&1 &
		json_out '{"ok":true,"msg":"已请求下线其他设备，本机将重新连接"}'
	else
		json_out '{"ok":true,"msg":"已请求下线其他设备"}'
	fi
}
