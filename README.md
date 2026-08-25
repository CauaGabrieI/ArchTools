# Arch Linux Smart Post-Install

Pós-instalador modular para Arch Linux. Ele detecta hardware, monta um plano, pede confirmação e só então executa. Não é um instalador do Arch: nunca particiona, formata, altera bootloader, aplica tuning agressivo ou reinicia o computador.

## Uso

```bash
chmod +x install.sh
./install.sh                         # modo interativo
./install.sh --desktop gnome --profile gaming --dry-run
./install.sh --detect-only
./install.sh --list-changes
./install.sh --rollback
./install.sh --uninstall
```

Desktops: `gnome`, `kde`, `xfce`, `cinnamon`, `hyprland`, `minimal`.
Perfis: `minimal`, `desktop`, `gaming`. O perfil gaming é o único que planeja suporte gráfico 32-bit.

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
