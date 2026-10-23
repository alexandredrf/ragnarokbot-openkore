#!/bin/sh
set -e

CONTROL=/data/control
LOGS=/data/logs
RUNTIME=/tmp/kore

# O container inicia como root so para acertar o dono das pastas montadas do host
# (numa VPS Linux, bots/<nome>/logs pode ter sido criado como root e o bot nao gravaria).
# Depois reexecuta este script como o usuario kore (uid 1000).
if [ "$(id -u)" = 0 ]; then
    mkdir -p "$CONTROL" "$LOGS"
    chown -R kore:kore "$CONTROL" "$LOGS"
    exec setpriv --reuid=kore --regid=kore --init-groups "$0" "$@"
fi

# Volume novo/vazio: copia os arquivos padrao do OpenKore (sem sobrescrever nada existente).
mkdir -p "$CONTROL" "$LOGS" "$RUNTIME"
cp -rn /opt/control.default/. "$CONTROL"/

# O OpenKore grava no config.txt tudo o que e digitado no console (inclusive a senha).
# Por isso ele roda sobre uma copia temporaria dentro do container: o config.txt
# versionado nunca recebe credenciais. Efeito colateral: "conf" no console nao persiste;
# altere bots/<nome>/control/config.txt.
cp "$CONTROL/config.txt" "$RUNTIME/config.txt"

# Credenciais opcionais vindas de bots/<nome>/account.env (ignorado pelo git).
# Sem elas, o OpenKore pergunta no console.
set_conf() {
    [ -n "$2" ] || return 0
    # Substitui (ou acrescenta) "chave valor" sem interpretar caracteres especiais do valor.
    KEY="$1" VAL="$2" perl -i -ne '
        if (/^\Q$ENV{KEY}\E(\s|$)/) { print "$ENV{KEY} $ENV{VAL}\n" unless $done++; next }
        print;
        print "$ENV{KEY} $ENV{VAL}\n" if eof && !$done;
    ' "$RUNTIME/config.txt"
}
set_conf username "$KORE_USERNAME"
set_conf password "$KORE_PASSWORD"
set_conf char "$KORE_CHAR"

cd /opt/openkore
exec perl openkore.pl --control="$CONTROL" --config="$RUNTIME/config.txt" --logs="$LOGS" "$@"
