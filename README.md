# ArchTools

A modular toolkit for detecting, configuring and managing Arch Linux systems.
ArchTools detecta hardware, monta planos explícitos e só executa alterações após confirmação. Não é um instalador do Arch: nunca particiona, formata, altera bootloader/EFI, instala AUR automaticamente, aplica tuning agressivo ou reinicia.

## Uso

```bash
chmod +x install.sh
./install.sh                         # fluxo completo interativo
./install.sh --desktop gnome --profile gaming --dry-run
./install.sh --detect-only
./install.sh --list-changes
./install.sh --rollback
./install.sh --uninstall
```

Desktops: `gnome`, `kde`, `xfce`, `cinnamon`, `hyprland`, `minimal`.
Perfis: `minimal`, `desktop`, `gaming`. O perfil gaming é o único que planeja suporte gráfico 32-bit.

## Ferramentas individuais

Cada entrypoint reutiliza os módulos de `hardware/`, `drivers/`, `desktop/`, `profiles/` e `services/`, sem chamar `install.sh` nem duplicar lógica:

```bash
./tools/hardware.sh
./tools/cpu.sh
./tools/gpu.sh --dry-run
./tools/storage.sh
./tools/network.sh
./tools/bluetooth.sh
./tools/audio.sh
./tools/desktop.sh gnome --dry-run
./tools/gaming.sh --dry-run
```

Ferramentas que alteram o sistema aceitam `--dry-run`, `--yes`, `--verbose` e `--help`; a ordem é sempre detectar, planejar, mostrar, confirmar, executar e validar. Ferramentas de detecção não modificam o sistema.

## Fluxo completo

```bash
./install.sh --desktop gnome --profile gaming
```

O fluxo continua sendo orquestrado por `install.sh`. A API interna em `lib/api.sh` é compartilhada por ele e pelas ferramentas, enquanto os módulos existentes continuam sendo os donos da lógica de detecção e planejamento.

## Segurança e estado

O programa usa `pacman --needed`, consulta a disponibilidade de cada pacote no repositório configurado e registra o que já existia separadamente do que ele instalou. O estado fica em `~/.local/state/arch-smart-postinstall/`; logs ficam em `logs/`. Rollback e uninstall só consideram os pacotes registrados pelo projeto. Backups devem ser criados com `backup_file` antes de qualquer futuro módulo modificar arquivos.

Para NVIDIA, o projeto não força cegamente o módulo de kernel: mostra a ressalva no plano e instala apenas a parte de espaço de usuário disponível. Confirme a compatibilidade com seu kernel e repositórios antes de incluir um módulo NVIDIA em uma extensão do projeto.

## Extensão

Um desktop expõe `desktop_nome`; um perfil expõe `profile_nome`; drivers adicionam pacotes através de `plan_package`. Assim os módulos permanecem separados de `install.sh`. Consulte o [guia detalhado de funcionamento](docs/how-it-works.md), [arquitetura](docs/architecture.md), [rollback](docs/rollback.md), a [verificação pós-auditoria](docs/post-audit-report.md), o [guia de VM](docs/vm-testing.md) e a [checklist de validação](docs/validation-checklist.md).

## Verificação

```bash
for test in tests/test_*.sh; do bash "$test"; done
shellcheck install.sh lib/*.sh hardware/*.sh drivers/*.sh desktop/*.sh profiles/*.sh services/*.sh
```
