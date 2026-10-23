# Bot OpenKore em Docker — RagnaWickeD

Roda o [OpenKore](https://github.com/OpenKore/openkore) em container, conectando por TCP direto ao
servidor privado RagnaWickeD (`137.131.220.233`, login 6900 / char 6121 / map 5121), sem navegador.

## Estado atual

| Item | Status |
|---|---|
| Imagem Docker | **OK**: build testado (Docker 29.8, OpenKore `e0b04ee` fixado, XSTools via `scons`, portais pré-compilados). |
| `servers.txt` | **OK**: `kRO_Ragexe_2018_10_31a`, charBlockSize 155, `itemListUseOldType 1`, sem ofuscação. |
| Login → char → map | **OK**: testado com a conta real (combate, coleta, inventário e `@storage` validados). |
| Farm Kyo Sinx | `xmas_dun02` (seção 6). |
| Farm Ashiba | `orcsdun01` (seção 6.1), testado: mata mortos-vivos com Cura. |
| Farm conta3 | `pay_dun01` (seção 6.2), testado: mata esqueletos, coleta só cartas e Maçã de Guilherme Tell. |

## Estrutura

```
Dockerfile            imagem (OpenKore + XSTools compilado + portais pré-compilados)
entrypoint.sh         popula o control vazio, injeta credenciais numa cópia temporária e inicia o bot
docker-compose.yml    um serviço por personagem
servers.txt           tabela de servidores (só o RagnaWickeD)
account.env.example   modelo do arquivo de credenciais
portals_ragnawicked.txt  NPCs de teleporte do servidor (entram na tabela de rotas no build)
plugins/fleeMonster/  plugin próprio: foge andando de monstros perigosos (montado no container)
tools/                gerador do pickupitems.txt
bots/<nome>/control/  config.txt, mon_control.txt, items_control.txt... (versionado, SEM senha)
bots/<nome>/account.env  credenciais (ignorado pelo git, opcional)
bots/<nome>/logs/     logs (ignorado pelo git)
```

## 1. Build

```
docker compose build
```

Para outra versão do OpenKore: `docker compose build --build-arg OPENKORE_REF=<commit ou master>`.

Ajustes que a imagem faz sobre o OpenKore puro:

- a árvore `/opt/openkore` pertence ao usuário `kore` (o OpenKore cria arquivos em `tables/`);
- `tables/translated/kRO_english/quests.txt` é limpo de bytes não-UTF-8 (defeito do upstream que aborta o bot);
- os NPCs de teleporte de `portals_ragnawicked.txt` são acrescentados ao `tables/portals.txt`;
- `tables/portalsLOS.txt` é gerado no build (senão cada container `--rm` recompila 522 mapas).

## 2. Credenciais (nunca em arquivo versionado)

O OpenKore grava no `config.txt` tudo o que é digitado no console, **inclusive a senha**. Por isso o
`entrypoint.sh` roda o bot sobre uma **cópia temporária** do config (`/tmp/kore/config.txt`, dentro do
container), e o `bots/<nome>/control/config.txt` versionado nunca recebe credenciais.

Duas opções:

- **Digitar no console**: deixe `username`/`password` vazios; o OpenKore pergunta ao iniciar.
- **Arquivo local**: copie `account.env.example` para `bots/<nome>/account.env` e preencha.
  Se a senha tiver `$`, use aspas simples: `KORE_PASSWORD='minha$enha'` (o compose interpreta `$`).

Efeito colateral: o comando `conf` no console do bot só vale até o container sair. Mudanças
permanentes vão em `bots/<nome>/control/config.txt`.

## 3. Executar

Todos os bots em segundo plano (um container por conta):

```
docker compose up -d              # ou só um: docker compose up -d ashiba
docker logs -f openkore-kyo       # acompanhar (Ctrl+C só fecha a visualização)
docker attach openkore-ashiba     # console; sair sem derrubar: Ctrl+P, Ctrl+Q
```

Depois de editar arquivos em `bots/<nome>/control/`: `docker compose restart <nome>`.
Depois de mudar `Dockerfile`, `portals_ragnawicked.txt` ou `docker-compose.yml`: `docker compose up -d --build`.

Comandos úteis no console: `s` (status), `i` (inventário), `skills`, `ai` (liga/desliga IA), `quit`.

## 4. Como o protocolo foi identificado

`window.ROConfig` do cliente web (roBrowser):

```
packetver 20181031, renewal false, version 55, langtype 12, packetKeys false, calculateHash false
```

Captura WebSocket do map server: o primeiro pacote enviado tem 19 B, `36 04 …` = `0x0436` (CZ_ENTER2)
com o layout padrão em claro, e o ping de 6 B é `0x0360`. São os mesmos opcodes do
`kRO_Ragexe_2018_10_31a` do OpenKore (cliente "main", não RE, porque o servidor é pré-renovação).

| Opção | Valor | Motivo |
|---|---|---|
| `serverType` | `kRO_Ragexe_2018_10_31a` | packetver exata |
| `version` / `master_version` | 55 / 12 | `version` e `langtype` do ROConfig |
| `charBlockSize` | 155 | EXP 64 bits (packetver ≥ 20170830) |
| `addTableFolders` | `translated/kRO_english;kRO/Ragexe_2018_11_14d;kRO` | recvpackets mais próximo |
| `masterLogin_packet` | `0064` | `calculateHash: false` → senha em texto |
| `itemListUseOldType` | 1 | inventário `0B09`/`0B0A` com ID de item de 2 bytes (24 B / 57 B por item, conferido em dump) |
| `sendCryptKeys` | — | `packetKeys: false`, opcodes em claro na captura |

## 5. Primeiro login

Validado: login → seleção de personagem (slot 1, `char 1` no config) → map server.

## 6. Farm — Kyo Sinx (`bots/kyo/control/`)

| Comportamento | Onde |
|---|---|
| Mapa fixo `xmas_dun02`, anda aleatoriamente procurando alvos | `lockMap`, `route_randomWalk 1` |
| Ataca só Presente (Myst Case 1249) e Soldadinho de Chumbo (Cruiser 1248); os demais só se atacarem primeiro | `mon_control.txt` (`all 0`) |
| Coleta tudo do chão | `pickupitems.txt` (`all 2`) |
| Ignora plantas, cogumelos e ovos (por ID; o servidor manda nomes em português) | `mon_control.txt` |
| White Potion com HP < 60% (Red Herb < 50% só se acabarem); senta com HP < 55% até 90% | `useSelf_item`, `sitAuto_hp_*` |
| Poção do Despertar sempre que o efeito acabar (só no mapa de farm, nível base ≥ 40, não com Berserk ativa) | `useSelf_item Awakening Potion` |
| Peso ≥ 50%: `@storage` ali mesmo e guarda tudo exceto consumíveis | `storageAuto*`, `itemsMaxWeight_sellOrStore`, `items_control.txt` |
| Usa Fly Wing para fugir se um MVP (lista completa pré-renovação) aparecer na tela | `mon_control.txt` (`-1 1`) |
| Foge **andando** do Filhote de Hatii (Garm Baby 1515, lento) quando chega a ≤ 10 células | plugin `fleeMonster` (`fleeMonster_*` no config) |
| Quando Bênção e Agilidade acabam em xmas_dun02: `@go 0` (o servidor buffa ao chegar em Prontera) | `macros.txt` (plugin macro) |
| Ao morrer (ou sempre que estiver em Prontera) volta pela Teletransportadora (prontera 163 190, 1ª opção) | `portals_ragnawicked.txt` (exige rebuild da imagem) |
| Não grava/recompila portais durante o jogo | `portalRecord 0` |

Para coletar só itens específicos (ex.: cartas, acessórios e Opala), gere o `pickupitems.txt` com
`tools/gen_pickupitems.pl`, que usa o item_db pré-renovação do rAthena
(instruções no cabeçalho do script). Para coletar outro item, passe o ID como argumento extra.

## 6.1 Farm — Ashiba (`bots/ashiba/control/`, conta 2)

Priest nível 71, Cura 10. Ataca mortos-vivos com Cura (dano sagrado) e ignora o resto.

| Comportamento | Onde |
|---|---|
| Mapa fixo `orcsdun01` (80 Orc Zumbi + 10 Orc Esqueleto) | `lockMap` |
| Ataca só Orc Zumbi (1153) e Orc Esqueleto (1152); todo o resto ignorado mesmo se atacar | `mon_control.txt` (`all -1`) |
| Ataque = Cura nível 10 a até 9 células, sem ataque físico | `attackSkillSlot Heal`, `attackUseWeapon 0` |
| Autocura com HP < 65%; Red Potion se HP < 50% e SP sem dar para a Cura | `useSelf_skill Heal`, `useSelf_item Red Potion` |
| HP < 30% ou SP < 10% no mapa: `@go 0` (o servidor cura/buffa na chegada) e volta pela Teletransportadora | `macros.txt` |
| `@autoloot 100` a cada entrada no jogo (coleta direta, sem andar até o item) | `macros.txt`, `itemsTakeAuto 0` |
| Peso ≥ 70%: `@storage` e guarda tudo exceto Red/Novice Potion e Blue Gemstone | `storageAuto*`, `items_control.txt` |

## 6.2 Farm — conta3 (`bots/conta3/control/`)

| Comportamento | Onde |
|---|---|
| Mapa fixo `pay_dun01`, entra pela Teletransportadora (opção 1) | `lockMap`, `portals_ragnawicked.txt` |
| Ataca tudo, exceto plantas e cogumelos. Só o Esqueleto Arqueiro (1016) dropa a Maçã de Guilherme Tell (Apple of Archer 2285, 0,03%) | `mon_control.txt` (`all 1`) |
| Coleta só cartas e Apple of Archer (2285/5265); o resto fica no chão | `pickupitems.txt` (`gen_pickupitems.pl ... 2285 5265 --sem-acessorios`) |
| Pontos de atributo sempre em Agilidade (até 99) | `statsAddAuto_list 99 agi` |
| Novice Potion com HP < 60% se não houver White Potion; repõe 200 do storage quando cai abaixo de 30 | `useSelf_item Novice Potion`, `getAuto Novice Potion` |
| Peso ≥ 50%: `@storage` e guarda tudo exceto consumíveis e flechas | `storageAuto*`, `items_control.txt` |
| Quando Bênção e Agilidade acabam no mapa: `@go 0` para rebuffar | `macros.txt` |

## 7. Vários personagens

1. Copie `bots/kyo/` para `bots/<novo>/` (sem o `account.env` e os `logs`).
2. Ajuste `char` (slot), `lockMap` e `fleeMonster_ids` no `config.txt` do novo personagem.
3. Em `docker-compose.yml`, copie o serviço `kyo` (incluindo o volume do plugin) com novo nome, `container_name`, caminho do `env_file`
   e dos volumes.
4. Se o mapa usa a Teletransportadora, acrescente a linha em `portals_ragnawicked.txt` e rode `docker compose up -d --build`.
5. Execute `docker compose up -d <novo>`. Cada conta roda em um container independente.

## 8. Rodar numa VPS (Linux)

Requisitos: Docker Engine com o plugin Compose (Ubuntu/Debian: `curl -fsSL https://get.docker.com | sh`).
O servidor do jogo é acessado por TCP direto nas portas 6900/6121/5121; nenhuma porta precisa ser aberta na VPS.

```bash
git clone https://github.com/<usuario>/<repo>.git bot && cd bot

# Credenciais (não vêm do git): uma por bot
cp account.env.example bots/kyo/account.env    && nano bots/kyo/account.env
cp account.env.example bots/ashiba/account.env && nano bots/ashiba/account.env
cp account.env.example bots/conta3/account.env && nano bots/conta3/account.env
chmod 600 bots/*/account.env

docker compose up -d --build     # build na primeira vez (~3 min) e sobe todos os bots
docker compose ps
docker logs -f openkore-ashiba
```

- `restart: unless-stopped`: os bots voltam sozinhos se a VPS reiniciar ou o processo cair.
  Para parar de vez: `docker compose stop` (ou `docker compose stop kyo`).
- O container inicia como root só para dar ao usuário `kore` (uid 1000) a posse de
  `bots/<nome>/control` e `bots/<nome>/logs`, e depois roda o bot como `kore`.
- A mesma conta não pode estar logada em dois lugares: desligue o bot local
  (`docker compose stop`) antes de subir na VPS.
- Atualizar: `git pull && docker compose up -d --build`.
