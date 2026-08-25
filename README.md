# ArchTools

> **Suíte modular de ferramentas para configuração, administração e manutenção do Arch Linux.**

ArchTools é um conjunto de ferramentas modulares para facilitar a **configuração, instalação de componentes, manutenção, diagnóstico e gerenciamento de sistemas Arch Linux**.

O projeto foi desenvolvido com foco em **modularidade, segurança, reutilização e controle sobre as alterações realizadas no sistema**.

Em vez de depender de um único script gigante, cada funcionalidade é separada em módulos que podem ser utilizados individualmente ou combinados através da CLI.

---

## ✨ Principais recursos

* 🧩 Arquitetura modular
* 🖥️ Suporte a diferentes ambientes desktop
* 🎮 Perfil para gaming
* 🔍 Detecção de hardware
* 🎮 Detecção e configuração de GPUs
* 📦 Gerenciamento de pacotes
* ⚙️ Gerenciamento de serviços
* 🧠 Sistema de planejamento de operações
* 🔄 Sistema de transações
* 💾 Backup e gerenciamento de estado
* ↩️ Rollback de alterações
* 🧪 Testes automatizados
* 🛡️ Validação antes da execução
* 🧾 Logs e registro das operações
* 🧪 Modo `dry-run`
* 🔎 Modo de detecção sem alterações
* 📋 Listagem das alterações realizadas

> **Nota:** o projeto está em desenvolvimento e deve ser testado em uma máquina virtual antes de ser utilizado em um sistema de produção.

---

# 🧱 Arquitetura

O ArchTools foi projetado para separar as responsabilidades do sistema.

```text
ArchTools
│
├── hardware/       # Detecção de hardware
├── drivers/        # Drivers e firmware
├── desktop/        # Ambientes gráficos
├── services/       # Serviços do sistema
├── profiles/       # Perfis de configuração
├── lib/            # Núcleo do sistema
├── tests/           # Testes
├── docs/            # Documentação
└── install.sh      # Interface principal
```

O núcleo fornece componentes reutilizáveis para os módulos:

```text
                    ArchTools
                        │
                ┌───────┴───────┐
                │      Core      │
                └───────┬───────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
     Detect          Planner         Modules
        │               │               │
        └───────────────┼───────────────┘
                        │
                    Executor
                        │
                   Transaction
                        │
             ┌──────────┴──────────┐
             │                     │
           State                 Logs
             │
        Backup / Rollback
```

A ideia é que os módulos não precisem implementar novamente toda a lógica de execução, validação, logging ou controle de estado.

---

# 🖥️ Ambientes desktop

Atualmente existem módulos para:

* GNOME
* KDE
* XFCE
* Cinnamon
* Hyprland
* Minimal

Exemplo:

```bash
./install.sh --desktop gnome
```

---

# 🎯 Perfis

O projeto possui perfis que agrupam configurações e componentes relacionados.

### Minimal

Instalação/configuração mínima.

### Desktop

Configuração voltada para uso geral em desktop.

### Gaming

Configuração voltada para jogos e componentes relacionados.

Exemplo:

```bash
./install.sh --desktop gnome --profile gaming
```

---

# 🔍 Detecção de hardware

O ArchTools possui módulos para detectar diferentes componentes do sistema.

Atualmente:

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

A detecção pode ser executada sem realizar alterações no sistema.

```bash
./install.sh --detect-only
```

---

# 🎮 Drivers

O projeto possui módulos específicos para:

* AMD
* Intel
* NVIDIA
* Wi-Fi
* Bluetooth
* Firmware

A intenção é permitir que o sistema detecte o hardware primeiro e utilize essa informação para planejar as alterações necessárias.

---

# ⚙️ Serviços

Existem módulos para gerenciamento de serviços como:

* áudio
* Bluetooth
* rede
* display manager
* impressão
* TRIM

Isso mantém a configuração de serviços separada dos demais componentes do sistema.

---

# 📦 Gerenciamento de pacotes

O ArchTools utiliza o gerenciador de pacotes do Arch Linux e possui uma camada própria para planejamento e controle das operações.

O sistema procura evitar instalações desnecessárias utilizando operações apropriadas do `pacman`.

As operações também podem ser registradas para permitir auditoria e recuperação.

---

# 🧠 Planejamento

Antes de realizar alterações, o ArchTools possui uma camada de planejamento.

O objetivo é separar:

```text
DETECT
  ↓
PLAN
  ↓
VALIDATE
  ↓
EXECUTE
```

Isso permite que uma operação seja analisada antes de modificar o sistema.

Por exemplo:

```bash
./install.sh --desktop gnome --profile gaming --dry-run
```

O modo `dry-run` permite visualizar o que seria realizado sem executar as alterações.

---

# 🔄 Transações

As alterações podem ser organizadas através do sistema de transações do ArchTools.

A ideia é evitar uma sequência descontrolada de comandos:

```text
comando 1
comando 2
comando 3
erro
```

Em vez disso:

```text
Planejar
   ↓
Validar
   ↓
Iniciar transação
   ↓
Executar
   ↓
Registrar
   ↓
Verificar
```

Isso também fornece uma base para recuperação de operações que falharam.

---

# 💾 Estado e backup

O ArchTools mantém informações sobre as operações realizadas pelo projeto.

O estado é armazenado em:

```text
~/.local/state/arch-smart-postinstall/
```

Essas informações são utilizadas para acompanhar alterações feitas pelo ArchTools.

O projeto também possui mecanismos de backup e recuperação.

---

# ↩️ Rollback

O sistema possui suporte para rollback das alterações registradas.

Exemplo:

```bash
./install.sh --rollback
```

O objetivo é permitir que alterações realizadas pelo ArchTools possam ser revertidas quando suportado pelo módulo envolvido.

> Rollback não significa que qualquer alteração feita no sistema poderá ser revertida automaticamente. O comportamento depende da operação e do módulo responsável.

---

# 🗑️ Desinstalação

O projeto possui suporte para remoção dos componentes que foram registrados como instalados pelo ArchTools.

```bash
./install.sh --uninstall
```

O objetivo é evitar que o ArchTools remova indiscriminadamente componentes que já existiam antes da execução.

---

# 📋 Auditoria e alterações

É possível consultar as alterações registradas pelo projeto:

```bash
./install.sh --list-changes
```

Isso permite verificar o que foi alterado antes de realizar operações de recuperação ou remoção.

---

# 🧪 Testes

O projeto possui uma suíte de testes para componentes do núcleo e módulos.

Exemplos:

```text
tests/
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

Também existem:

```text
tests/fixtures/
tests/mock-bin/
```

que permitem testar determinados comportamentos sem depender diretamente de uma máquina física.

---

# 🚀 Uso

Clone o projeto:

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

---

## 🔎 Detectar o sistema

```bash
./install.sh --detect-only
```

---

## 🧪 Simular uma instalação

```bash
./install.sh --desktop gnome --profile gaming --dry-run
```

---

## 📋 Ver alterações

```bash
./install.sh --list-changes
```

---

## ↩️ Fazer rollback

```bash
./install.sh --rollback
```

---

## 🗑️ Desinstalar componentes registrados

```bash
./install.sh --uninstall
```

---

# 🛡️ Segurança

O ArchTools foi projetado para evitar operações destrutivas desnecessárias.

O projeto atualmente **não tem como objetivo**:

* particionar discos automaticamente;
* formatar discos;
* apagar partições;
* substituir o bootloader;
* reiniciar o sistema automaticamente.

Operações que podem alterar o sistema devem ser tratadas de maneira controlada e, sempre que possível, passar por:

```text
detecção
   ↓
planejamento
   ↓
validação
   ↓
execução
   ↓
registro
```

Mesmo assim, **sempre revise o que será executado antes de utilizar o projeto em uma máquina importante**.

---

# 🧪 Status do projeto

**Estado:** desenvolvimento / pré-produção.

A arquitetura principal já está estabelecida, mas o projeto ainda está passando por testes em ambientes reais e máquinas virtuais.

O objetivo atual é:

1. validar os módulos existentes;
2. corrigir problemas encontrados;
3. melhorar a confiabilidade;
4. ampliar a cobertura de testes;
5. somente depois adicionar novas funcionalidades importantes.

---

# 🗺️ Roadmap

O ArchTools está sendo desenvolvido de forma incremental.

Possíveis evoluções futuras:

* Snapshot de configuração
* Diff entre estados
* Estado desejado
* Aplicação de configurações
* Verificação pós-execução
* `doctor`
* `repair`
* Auditoria avançada
* Configuração declarativa
* Exportação/importação de configurações
* Gerenciamento de dotfiles
* Módulos externos
* Sistema de plugins
* Interface TUI

Essas funcionalidades fazem parte da visão futura do projeto e **não devem ser consideradas implementadas até que estejam oficialmente incorporadas e testadas**.

---

# 📁 Estrutura do projeto

```text
ArchTools/
├── desktop/
├── docs/
├── drivers/
├── examples/
├── hardware/
├── lib/
├── profiles/
├── services/
├── tests/
│   ├── fixtures/
│   └── mock-bin/
├── .gitignore
├── CHANGELOG.md
├── LICENSE
├── README.md
├── VERSION
└── install.sh
```

---

# 🤝 Contribuição

Contribuições são bem-vindas.

Antes de criar um novo módulo, procure manter a arquitetura modular existente.

Um módulo deve, sempre que possível:

* possuir uma responsabilidade clara;
* evitar duplicação de lógica do Core;
* ser seguro para execução repetida;
* utilizar as APIs existentes;
* possuir testes;
* registrar adequadamente suas alterações;
* evitar operações destrutivas sem necessidade.

---

# 📜 Licença

Este projeto é distribuído sob os termos definidos no arquivo [`LICENSE`](LICENSE).

---

## 🎯 Filosofia

ArchTools não pretende ser apenas um instalador.

A visão do projeto é criar uma **caixa de ferramentas modular para Arch Linux**, onde cada ferramenta possa ser utilizada individualmente e várias ferramentas possam ser combinadas para realizar tarefas maiores.

```text
        Ferramentas independentes
                  │
                  ↓
             Core comum
                  │
        ┌─────────┴─────────┐
        ↓                   ↓
   Configuração          Manutenção
        │                   │
        └─────────┬─────────┘
                  ↓
              Arch Linux
```

**Modular. Controlável. Reutilizável.**
