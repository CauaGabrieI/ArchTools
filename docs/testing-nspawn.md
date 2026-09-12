# Testes do ArchTools com systemd-nspawn

Esta infraestrutura cria um Arch Linux mínimo descartável em `/var/lib/machines/archtools-base` e executa o ArchTools **somente** em `/var/lib/machines/archtools-test`. A base não recebe testes e, em Btrfs, fica como subvolume somente leitura. O script se recusa a sobrescrever diretórios existentes. Nenhuma instalação do ArchTools é executada no CachyOS host.

## Requisitos e arquitetura

Execute a partir de um host Arch/CachyOS com systemd, pacman, sudo e espaço em `/var/lib/machines`. O script verifica `systemd-nspawn`, `machinectl`, `pacstrap`, `git` e ferramentas auxiliares. Em Arch, `systemd-nspawn`/`machinectl` vêm de [systemd](https://archlinux.org/packages/core/x86_64/systemd/files/), `pacstrap` de [arch-install-scripts](https://archlinux.org/packages/extra/any/arch-install-scripts/files/) e `git` de [git](https://archlinux.org/packages/extra/x86_64/git/files/). Se faltar algo, o script mostra o comando `sudo pacman -S --needed ...`; ele **não** instala dependências no host. No CachyOS, confira o provedor local com `pacman -Qo /usr/bin/systemd-nspawn /usr/bin/machinectl`.

`setup` usa `pacstrap -K -M` com configuração própria contendo apenas os repositórios oficiais Arch `core`, `extra` e `multilib`, apontados para `geo.mirror.pkgbuild.com`. Isso evita reutilizar os repositórios CachyOS do host. A base instala `base`, `sudo`, `dbus` e `diffutils` (necessário para a suíte), sem kernel, bootloader ou desktop. O setup verifica atualização das bases do pacman pela rede e systemd no **teste**, então para e restaura o teste, deixando-o limpo.

O checkout atual é montado em `/opt/ArchTools` com `--bind-ro`, incluindo alterações ainda não commitadas. Instalações reais usam uma cópia em `/root/ArchTools-work` **dentro do container**; logs, estado e transações ficam ali e em `/root/.local/state`, sem escrita no checkout host. `run --writable` e `shell --writable` também selecionam essa cópia. Alterações posteriores no checkout host aparecem no mount somente leitura; recrie a cópia interna com `reset` para um teste controlado.

O container inicia como unidade transitória `archtools-nspawn-test.service` via `systemd-run`, com PID 1 systemd, user namespace, checkout somente leitura e `CAP_NET_ADMIN`/`CAP_NET_RAW` removidas. A rede é compartilhada com o host para usar pacman sem configurar NAT, bridges ou serviços globais no CachyOS. Essa escolha permite acesso de rede do container, mas **não isola o tráfego** do host. O script não edita configuração global; a unidade transitória e o registro do machinectl existem somente enquanto o container roda. Não execute código não confiável no container como se fosse uma barreira de segurança equivalente a uma VM.

O filesystem de `/var/lib/machines` é detectado com `findmnt`. Em Btrfs, `reset` usa snapshot gravável da base somente leitura. Nos demais filesystems, usa `cp -a --reflink=auto`, que tenta reflink e recorre a cópia normal quando necessário. As únicas raízes removíveis são `/var/lib/machines/archtools-base` e `/var/lib/machines/archtools-test`, após checagem de marcador de propriedade, symlinks e mountpoints. Em Btrfs, subvolumes internos só podem ser removidos nos caminhos fixos `var/lib/machines` e `var/lib/portables` dentro dessas raízes. Falhas deixam o ambiente para inspeção; `destroy` remove somente ambientes marcados como pertencentes a esta infraestrutura.

## Fluxo diário

```bash
./tools/testing/nspawn.sh status
./tools/testing/nspawn.sh setup
./tools/testing/nspawn.sh start
./tools/testing/nspawn.sh shell
./tools/testing/nspawn.sh run './archtools doctor'
./tools/testing/nspawn.sh test
./tools/testing/nspawn.sh stop
./tools/testing/nspawn.sh reset
./tools/testing/nspawn.sh destroy
```

`setup` só funciona quando ambos os nomes estão livres. Se encontrar algo existente, use `status` e decida explicitamente entre preservar e `destroy`; arquivos sem o marcador correto nunca são removidos pelo script. `start` inicia somente `archtools-test`; `stop` o para. `reset` para o teste, remove somente o teste identificado e o recria da base. `destroy` também remove a base. `--dry-run` mostra o plano sem alterações, por exemplo `reset --dry-run` ou `setup --dry-run`. Use `--verbose` para ver comandos executados.

Para trabalhar com arquivos modificáveis no projeto sem escrever no checkout host:

```bash
./tools/testing/nspawn.sh shell --writable
./tools/testing/nspawn.sh run --writable './install.sh --hardware-profile vm --usage-profile minimal --desktop minimal --yes'
```

Passe o comando de `run` como **uma string entre aspas**. O `--dry-run` do ambiente é opção do script; o `--dry-run` dentro da string pertence ao ArchTools. Você também pode usar `run -- './install.sh --dry-run'`.

## Testes rápidos e integração

```bash
./tools/testing/nspawn.sh test
./tools/testing/nspawn.sh test integration           # minimal real
./tools/testing/nspawn.sh test integration desktop   # GNOME real, pesado
./tools/testing/nspawn.sh test integration development
./tools/testing/nspawn.sh test integration server
./tools/testing/nspawn.sh test integration gaming-dry-run
```

`test` roda os testes Bash do ArchTools (exceto `tests/test_nspawn.sh`, que valida o host), `bash -n`, `doctor`, detecção e dry-runs minimal, GNOME e development. Rode `bash tests/test_nspawn.sh` no host para verificar os guards do orquestrador. O comando reporta PASS/FAIL e retorna código não zero se falhar. Não instala GNOME automaticamente. Cada teste de integração começa com `reset` e usa perfis `--hardware-profile vm`. `integration` sem cenário realiza instalação minimal real. `gaming-dry-run` nunca instala pacotes. O plano deve ser revisado antes de um cenário pesado; o comando `integration desktop` é uma escolha explícita para instalar GNOME dentro do container.

Os testes reais usam `--yes` apenas após selecionar explicitamente o perfil e desktop; eles nunca executam `./install.sh` no host. Para inspecionar manualmente um serviço dentro do container, use `systemctl is-enabled`, `systemctl is-active` e `systemctl status`. A saída automatizada separa enablement de runtime (`running`, `failed`, `inactive`, `not-installed` ou `unsupported-in-container`). Um serviço pode aparecer como `enabled + inactive` dentro do container; isso não equivale a falha de habilitação. Quando o isolamento impede um serviço de iniciar, valide apenas o estado que o container consegue observar.

## Idempotência e rollback

```bash
./tools/testing/nspawn.sh test idempotency
./tools/testing/nspawn.sh test rollback
```

Ambos começam de uma cópia limpa. Idempotência instala o perfil minimal duas vezes e compara pacotes instalados, arquivos/serviços gerenciados, metadados dos arquivos de estado e backups, e eventos da segunda transação. O segundo run deve ter zero alterações registradas. Rollback registra os pacotes e o enablement de NetworkManager antes da instalação, executa o rollback do ArchTools e verifica pacotes gerenciados, estado, serviço, transação e `list-changes`. Caches do pacman, dependências não gerenciadas e journals são excluídos da comparação; o histórico é validado por resultado, sem comparação byte a byte. `test failure` reserva um ponto de extensão, mas retorna erro claro sem injetar falhas.

## Limites do container

`systemd-nspawn` verifica lógica de pacotes, planejamento, transações, estado, backup, rollback, idempotência e operações de enable/disable de services. Ele **não valida** boot real, kernel real, bootloader, initramfs, GPU física, drivers gráficos reais, sessão GNOME/KDE real, GDM/SDDM abrindo interface, Wayland/X11 real, Wi-Fi/Bluetooth físico, energia/bateria, suspensão ou monitor. Para esses casos, mantenha [testes em VM](vm-testing.md) ou hardware real. A detecção de virtualização deve mostrar `systemd-nspawn`; a GPU do host, mesmo visível via `/sys`, é tratada como não verificável no container.

Se a inicialização falhar, consulte `journalctl -u archtools-nspawn-test.service` e `status`; não execute `rm -rf` manualmente. Um kernel/filesystem sem suporte a user namespace com idmapped mount pode recusar `start`; o script não desativa esse isolamento automaticamente. Rede, firmware e alguns services físicos também podem ter limitações próprias de container.
