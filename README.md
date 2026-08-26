# ArchTools

<p align="center">
  <strong>Uma suíte modular de ferramentas para configurar, administrar e manter o Arch Linux.</strong>
</p>

<p align="center">
  <a href="https://github.com/CauaGabrieI/ArchTools">
    <img src="https://img.shields.io/badge/platform-Arch%20Linux-1793D1?logo=arch-linux&logoColor=white" alt="Platform">
  </a>
  <a href="https://github.com/CauaGabrieI/ArchTools/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/CauaGabrieI/ArchTools" alt="License">
  </a>
  <a href="https://github.com/CauaGabrieI/ArchTools">
    <img src="https://img.shields.io/github/stars/CauaGabrieI/ArchTools?style=flat" alt="Stars">
  </a>
  <a href="https://github.com/CauaGabrieI/ArchTools/commits/main">
    <img src="https://img.shields.io/github/last-commit/CauaGabrieI/ArchTools" alt="Last commit">
  </a>
</p>

<p align="center">
  <a href="#-instalação">Instalação</a> •
  <a href="#-uso">Uso</a> •
  <a href="#-visão-geral">Visão geral</a> •
  <a href="#-recursos">Recursos</a> •
  <a href="#-arquitetura">Arquitetura</a> •
  <a href="#-testes">Testes</a> •
  <a href="#-roadmap">Roadmap</a>
</p>

---

# 🚀 Instalação

Clone o repositório:

```bash
git clone https://github.com/CauaGabrieI/ArchTools.git
cd ArchTools
```

Dê permissão de execução:

```bash
chmod +x install.sh
```

Execute:

```bash
./install.sh
```

> **Recomendação:** teste o ArchTools primeiro em uma máquina virtual ou instalação Arch Linux de testes antes de utilizá-lo no sistema principal.

---

# 💻 Uso

## Ajuda

```bash
./install.sh --help
```

## Detectar hardware

Executa a detecção sem realizar a instalação/configuração:

```bash
./install.sh --detect-only
```

## Simular uma operação

Use `--dry-run` para visualizar o que seria executado:

```bash
./install.sh --desktop gnome --profile gaming --dry-run
```

## Configurar um desktop

```bash
./install.sh --desktop gnome --profile desktop
```

O desktop core contém apenas a sessão e os serviços essenciais. Terminal,
navegador, loja, gerenciador de arquivos, editor e compactador são componentes
opcionais e só entram no plano quando selecionados explicitamente:

```bash
./install.sh --desktop gnome --profile desktop \
  --desktop-components terminal,browser,files
```

Use `all` para selecionar todas as seis categorias ou `none` para nenhuma:

```bash
./install.sh --desktop kde --profile desktop --desktop-components all
./install.sh --desktop xfce --profile desktop --desktop-components none
```

`--yes` apenas confirma um plano já selecionado. Ele nunca equivale a
`--desktop-components all`.

## Componentes de desktop standalone

Detecte o desktop atual e veja sugestões sem criar logs, estado ou transações:

```bash
./archtools desktop-apps suggest
./archtools desktop-apps suggest --desktop kde
```

Planeje ou instale somente as categorias escolhidas:

```bash
./archtools desktop-apps install terminal --desktop gnome --dry-run
./archtools desktop-apps install terminal,browser,store --desktop kde
```

Categorias válidas:

```text
terminal browser store files editor archive all none
```

Ambientes suportados: GNOME, KDE Plasma, XFCE, Cinnamon e Hyprland. O perfil
`minimal` não recebe sugestões automáticas. Desktop desconhecido exige
`--desktop` explícito antes de qualquer instalação.

## Configurar um perfil de gaming

```bash
./install.sh --profile gaming
```

## Listar alterações

```bash
./install.sh --list-changes
```

## Rollback

```bash
./install.sh --rollback
```

## Desinstalar componentes registrados

```bash
./install.sh --uninstall
```

---

## 📋 Referência rápida da CLI

| Comando/opção      | Função                         |
| ------------------ | ------------------------------ |
| `./install.sh`     | Executa o fluxo principal      |
| `--help`           | Exibe a ajuda                  |
| `--detect-only`    | Detecta o sistema sem instalar |
| `--dry-run`        | Simula a operação              |
| `--desktop <nome>` | Seleciona o ambiente desktop   |
| `--desktop-components <lista>` | Seleciona componentes opcionais explicitamente |
| `--profile <nome>` | Seleciona o perfil             |
| `--list-changes`   | Lista alterações registradas   |
| `--rollback`       | Reverte alterações suportadas  |
| `--uninstall`      | Remove componentes registrados |

### Exemplos

```bash
# Detectar o hardware
./install.sh --detect-only

# Simular configuração GNOME + Gaming
./install.sh --desktop gnome --profile gaming --dry-run

# Aplicar configuração GNOME + Gaming
./install.sh --desktop gnome --profile gaming

# Simular GNOME com terminal e navegador opcionais
./install.sh --desktop gnome --profile desktop \
  --desktop-components terminal,browser --dry-run

# Sugestões somente leitura
./archtools desktop-apps suggest

# Ver alterações
./install.sh --list-changes

# Reverter alterações suportadas
./install.sh --rollback
```

---

# 🧭 Visão geral

**ArchTools** é uma suíte modular de ferramentas para **Arch Linux**.

O projeto busca facilitar tarefas que normalmente exigem vários scripts, comandos e configurações manuais, mantendo cada funcionalidade separada e reutilizável.

Em vez de criar um único script gigante, o ArchTools organiza suas funcionalidades em módulos:

```text
Hardware
   │
Drivers
   │
Desktop
   │
Services
   │
Profiles
   │
Packages
   │
   ▼
   Core
   │
   ├── Planner
   ├── Executor
   ├── Transactions
   ├── State
   ├── Backup
   ├── Rollback
   └── Logger
```

A ideia central é:

> **Ferramentas pequenas, independentes e combináveis.**

---

# ✨ Recursos

## 🧩 Arquitetura modular

Funcionalidades são separadas por responsabilidade:

```text
hardware/
drivers/
desktop/
services/
profiles/
lib/
tests/
```

Isso facilita manutenção, testes e expansão do projeto.

---

## 🔍 Detecção de hardware

Módulos para identificar componentes do sistema:

* CPU
* GPU
* memória
* armazenamento
* rede
* Wi-Fi
* Bluetooth
* áudio
* monitor
* boot
* virtualização
* laptop/notebook

---

## 🎮 Drivers

Suporte modular para:

* AMD
* Intel
* NVIDIA
* Wi-Fi
* Bluetooth
* Firmware

---

## 🖥️ Ambientes desktop

Módulos disponíveis para:

* GNOME
* KDE
* XFCE
* Cinnamon
* Hyprland
* Minimal

---

## 🎯 Perfis

Configurações agrupadas por objetivo:

| Perfil    | Objetivo                         |
| --------- | -------------------------------- |
| `minimal` | Sistema mínimo                   |
| `desktop` | Uso geral                        |
| `gaming`  | Jogos e componentes relacionados |

Exemplo:

```bash
./install.sh --desktop gnome --profile gaming
```

---

## ⚙️ Serviços

Módulos para serviços comuns:

* Áudio
* Bluetooth
* Rede
* Display Manager
* Impressão
* TRIM

---

## 📦 Gerenciamento de pacotes

O ArchTools possui uma camada para planejamento e controle de pacotes utilizando o ecossistema do Arch Linux.

O objetivo é evitar operações desnecessárias e manter registro das alterações realizadas.

---

## 🧠 Planner

As operações passam por uma etapa de planejamento:

```text
┌──────────────┐
│   Detect     │
└──────┬───────┘
       ↓
┌──────────────┐
│    Plan      │
└──────┬───────┘
       ↓
┌──────────────┐
│   Validate   │
└──────┬───────┘
       ↓
┌──────────────┐
│   Execute    │
└──────────────┘
```

---

## 🧪 Dry-run

Permite analisar uma operação sem aplicá-la:

```bash
./install.sh --desktop gnome --profile gaming --dry-run
```

---

## 🔄 Transactions

Operações podem ser organizadas através de um sistema de transações:

```text
Request
   ↓
Detect
   ↓
Plan
   ↓
Validate
   ↓
Transaction
   ↓
Execute
   ↓
Record
```

---

## 💾 State

O ArchTools mantém informações sobre operações realizadas pelo projeto.

Estado:

```text
~/.local/state/arch-smart-postinstall/
```

Essas informações são utilizadas pelos mecanismos de auditoria, backup e rollback.

---

## 💾 Backup

O projeto possui mecanismos para registrar e preservar informações necessárias para recuperação das alterações suportadas.

---

## ↩️ Rollback

Alterações registradas podem ser revertidas quando suportadas pela operação:

```bash
./install.sh --rollback
```

---

## 📋 Auditoria

Consulte as alterações registradas:

```bash
./install.sh --list-changes
```

---

# 🏗️ Arquitetura

O ArchTools é dividido em duas camadas principais:

```text
                    ┌───────────────────────┐
                    │       install.sh      │
                    │      CLI / Entry      │
                    └───────────┬───────────┘
                                │
                                ▼
                    ┌───────────────────────┐
                    │         CORE          │
                    │                       │
                    │ CLI / API             │
                    │ Planner               │
                    │ Executor              │
                    │ Transactions          │
                    │ State                 │
                    │ Backup                │
                    │ Rollback              │
                    │ Logger                │
                    │ Validator             │
                    └───────────┬───────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
       ┌────────────┐    ┌────────────┐    ┌────────────┐
       │  Hardware  │    │  Drivers   │    │  Desktop   │
       └────────────┘    └────────────┘    └────────────┘
              │                 │                 │
              └─────────────────┼─────────────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
       ┌────────────┐    ┌────────────┐    ┌────────────┐
       │  Services  │    │  Profiles  │    │  Packages  │
       └────────────┘    └────────────┘    └────────────┘
```

## 📁 Estrutura

```text
ArchTools/
│
├── desktop/
├── drivers/
├── hardware/
├── lib/
├── profiles/
├── services/
├── tests/
│   ├── fixtures/
│   └── mock-bin/
├── docs/
├── examples/
├── install.sh
├── CHANGELOG.md
├── VERSION
└── LICENSE
```

---

# 🧪 Testes

O projeto possui testes para componentes como:

* CLI
* CPU
* GPU
* Network
* Storage
* Packages
* Modules
* Backup
* Preflight
* Dry-run
* Transactions

Também existem testes de integração e ciclo de vida das transações.

```text
tests/
├── fixtures/
├── mock-bin/
├── test_backup.sh
├── test_cli.sh
├── test_cpu.sh
├── test_dry_run.sh
├── test_gpu.sh
├── test_modules.sh
├── test_network.sh
├── test_packages.sh
├── test_preflight.sh
├── test_storage.sh
├── test_tools.sh
├── test_transaction.sh
├── test_transaction_integration.sh
└── test_transaction_lifecycle.sh
```

> Antes de considerar uma versão pronta para produção, o projeto deve ser validado em uma instalação Arch Linux limpa, preferencialmente em uma máquina virtual.

---

# 🛡️ Segurança

O ArchTools foi projetado para minimizar operações destrutivas.

Atualmente, o projeto não tem como objetivo:

```text
❌ Particionar discos automaticamente
❌ Formatar discos
❌ Apagar partições
❌ Substituir o bootloader
❌ Reiniciar o sistema automaticamente
```

O fluxo esperado é:

```text
┌───────────┐
│  Detect   │
└─────┬─────┘
      ↓
┌───────────┐
│   Plan    │
└─────┬─────┘
      ↓
┌───────────┐
│ Validate  │
└─────┬─────┘
      ↓
┌───────────┐
│  Execute  │
└─────┬─────┘
      ↓
┌───────────┐
│   State   │
└───────────┘
```

Mesmo assim, **sempre revise operações antes de executá-las em um sistema importante**.

---

# 🧪 Status

> **Development / Pre-production**

O ArchTools possui uma arquitetura funcional e uma suíte inicial de testes, mas ainda está em fase de validação.

Objetivo atual:

```text
Testar
  ↓
Encontrar problemas
  ↓
Corrigir
  ↓
Testar novamente
  ↓
Estabilizar
```

Novas funcionalidades maiores serão adicionadas depois que a base atual estiver suficientemente validada.

---

# 🗺️ Roadmap

## Core

* [x] CLI
* [x] Planner
* [x] Executor
* [x] State
* [x] Logger
* [x] Transactions
* [x] Backup
* [x] Rollback
* [x] Validation
* [x] Dry-run
* [ ] API de módulos totalmente padronizada
* [ ] Dependências entre módulos
* [ ] Sistema de conflitos

## Configuração

* [ ] Snapshots
* [ ] Diff de estados
* [ ] Estado desejado
* [ ] Apply declarativo
* [ ] Verify pós-execução
* [ ] Export/import de configurações
* [ ] Dotfiles

## Manutenção

* [ ] `doctor`
* [ ] `repair`
* [ ] `update`
* [ ] `cleanup`
* [ ] `optimize`
* [ ] Auditoria avançada

## Ecossistema

* [ ] Módulos externos
* [ ] Catálogo de módulos
* [ ] Versionamento de módulos
* [ ] Sistema de plugins
* [ ] TUI

---

# 🎯 Filosofia do projeto

ArchTools não pretende ser apenas um instalador.

A visão é criar uma **suíte de ferramentas modulares para todo o ciclo de vida de um sistema Arch Linux**.

```text
                  ARCH LINUX
                      │
                      ▼
                 ┌──────────┐
                 │ ArchTools│
                 └────┬─────┘
                      │
       ┌──────────────┼──────────────┐
       ▼              ▼              ▼
   Configure       Maintain       Diagnose
       │              │              │
       ▼              ▼              ▼
   Hardware        Updates         Doctor
   Drivers         Cleanup         Repair
   Desktop         Services        Audit
   Packages        System
       │
       └──────────────┬──────────────┘
                      ▼
                 Recover / Rollback
```

Cada ferramenta deve ter uma responsabilidade clara.

Cada módulo deve poder ser reutilizado.

E operações maiores devem ser construídas **combinando módulos existentes**, em vez de duplicar lógica.

---

# 🤝 Contribuindo

Contribuições são bem-vindas.

Ao criar ou modificar um módulo:

* mantenha uma responsabilidade clara;
* evite duplicar funcionalidades do Core;
* prefira operações idempotentes;
* valide entradas;
* registre alterações importantes;
* adicione testes;
* evite operações destrutivas;
* mantenha a documentação atualizada.

---

# 📜 Licença

Consulte [`LICENSE`](LICENSE) para os termos da licença do projeto.

---

# 🔗 Links

**Repositório:**
https://github.com/CauaGabrieI/ArchTools

---

<p align="center">
  <strong>ArchTools</strong><br>
  Modular tools for Arch Linux.
</p>
