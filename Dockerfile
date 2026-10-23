# OpenKore em Debian 12. O build usa scons (o Makefile do OpenKore so envolve o scons).
FROM debian:bookworm-slim

ARG OPENKORE_REPO=https://github.com/OpenKore/openkore.git
# Commit testado (build + startup OK em 2026-10-22). Use --build-arg OPENKORE_REF=master para a ultima versao.
ARG OPENKORE_REF=e0b04ee7090ff0bc9ab0fa6b876756c4b9004770

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 TERM=xterm

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates git perl libperl-dev build-essential scons python3 \
        libreadline-dev libcurl4-openssl-dev zlib1g-dev libncurses-dev \
    && rm -rf /var/lib/apt/lists/*

# O OpenKore escreve em tables/ (ex.: cria monsters.txt), entao a arvore pertence ao usuario kore.
RUN useradd -m -u 1000 kore \
    && install -d -o kore -g kore /opt/openkore /opt/control.default /data /data/control /data/logs

USER kore
WORKDIR /opt/openkore
RUN git clone "$OPENKORE_REPO" /opt/openkore \
    && cd /opt/openkore && git checkout "$OPENKORE_REF" \
    && scons \
    # quests.txt traduzido tem bytes nao-UTF-8 no upstream e o OpenKore aborta ao carrega-lo.
    && f=tables/translated/kRO_english/quests.txt \
    && iconv -f UTF-8 -t UTF-8 -c "$f" > "$f.tmp" && mv "$f.tmp" "$f" \
    && rm -rf .git src/test/*.o \
    && cp -r control/. /opt/control.default/

# NPCs de teleporte do servidor entram na tabela de portais antes da compilacao abaixo.
COPY --chown=kore:kore portals_ragnawicked.txt /tmp/portals_ragnawicked.txt
RUN printf '\n# --- RagnaWickeD (portals_ragnawicked.txt) ---\n' >> tables/portals.txt \
    && grep -v '^\s*#' /tmp/portals_ragnawicked.txt | grep -v '^\s*$' >> tables/portals.txt \
    && rm /tmp/portals_ragnawicked.txt \
    # gef_fild14 falta na tabela de mapas do upstream: sem ele o lockMap e recusado ("doesn't exist").
    && printf 'gef_fild14.rsw#Geffen Field\n' >> tables/translated/kRO_english/maps.txt

# Pre-compila tables/portalsLOS.txt (senao cada container --rm leva minutos recompilando).
# Usa a entrada "Localhost" do servers.txt original so para passar do carregamento de tabelas;
# o processo e encerrado assim que o arquivo e gravado (antes de qualquer conexao util).
RUN cp -r /opt/control.default /tmp/ctl \
    && sed -i 's/^portalCompile.*/portalCompile 1/; s/^master$/master Localhost/; s/^username$/username build/; s/^password$/password build/' /tmp/ctl/config.txt \
    && (perl openkore.pl --control=/tmp/ctl --logs=/tmp/logs < /dev/null > /tmp/build.log 2>&1 & pid=$!; \
        i=0; while [ $i -lt 1200 ] && [ ! -s tables/portalsLOS.txt ] && kill -0 $pid 2>/dev/null; do sleep 2; i=$((i+2)); done; \
        sleep 5; kill $pid 2>/dev/null; wait $pid 2>/dev/null; true) \
    && { test -s tables/portalsLOS.txt || { cat /tmp/build.log; exit 1; }; } \
    && rm -rf /tmp/ctl /tmp/logs /tmp/build.log

COPY --chmod=755 entrypoint.sh /entrypoint.sh

# O entrypoint comeca como root (acerta permissoes dos volumes) e cai para kore.
USER root
ENTRYPOINT ["/entrypoint.sh"]
