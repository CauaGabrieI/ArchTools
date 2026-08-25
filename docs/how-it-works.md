# Como o sistema funciona

O Arch Linux Smart Post-Install é um pós-instalador: ele configura um Arch Linux já instalado, mas não cria partições, formata discos, instala o sistema-base ou altera o bootloader. A regra central é que a detecção nunca executa alterações por conta própria.

## Fluxo de execução

```text
Argumentos/seleções
        ↓
Detectar hardware e estado atual
        ↓
Analisar os resultados
        ↓
Decidir módulos e pacotes compatíveis
        ↓
Montar e exibir o plano
        ↓
Confirmar
        ↓
Executar o plano
        ↓
Validar o resultado
        ↓
Salvar estado e apresentar relatório
```

`install.sh` é somente o ponto de entrada. Ele carrega `lib/core.sh`, que interpreta os argumentos, inicializa log e estado, e coordena o fluxo. A lógica fica separada nos diretórios `hardware`, `drivers`, `desktop`, `profiles`, `services` e `lib`.

## 1. Entrada e argumentos

O modo normal pode ser interativo:

```bash
./install.sh
```

Ou receber as decisões diretamente:

```bash
./install.sh --desktop gnome --profile gaming
```

Os desktops disponíveis são `gnome`, `kde`, `xfce`, `cinnamon`, `hyprland` e `minimal`. Os perfis são `minimal`, `desktop` e `gaming`.

`--dry-run` percorre tudo até a criação do plano, mas não usa `pacman`, `sudo` ou `systemctl`, nem cria logs ou estado persistente. `--detect-only` apenas exibe a detecção. `--help` funciona sem criar logs ou estado.

## 2. Detecção

Os detectores preenchem o array central `HARDWARE`. Os módulos seguintes não precisam executar novamente comandos como `lspci`: eles consultam esse conjunto de dados.

| Área | Fontes principais | Resultado usado pelo plano |
| --- | --- | --- |
| CPU | `lscpu` | fabricante, modelo, arquitetura e virtualização da CPU |
| GPU | `lspci -nnk`, `glxinfo`, `vulkaninfo` | todas as GPUs e seus fornecedores |
| Memória | `free` | total e disponível, apenas para informação |
| Discos | `lsblk`, `findmnt` | tipo, disco raiz, filesystem e elegibilidade de TRIM |
| Rede | `ip`, `iw`, `lspci` | interfaces e presença de Wi-Fi |
| Bluetooth | `bluetoothctl`, `lsusb`, `lspci` | presença de adaptador Bluetooth |
| Máquina | bateria e `systemd-detect-virt` | desktop, notebook ou VM |
| Boot/monitor/áudio | DRM, `/sys/firmware/efi`, systemd | dados informativos e estado da pilha de áudio |

Ferramentas opcionais ausentes reduzem os dados disponíveis; elas não interrompem desnecessariamente a detecção. O programa exige `pacman` antes de criar um plano de instalação, pois o alvo é Arch Linux ou uma distribuição compatível.

## 3. Decisão e plano

Os módulos só chamam `plan_package` e `add_service`; essas funções colocam itens em listas na memória e evitam duplicatas. Neste ponto nenhum pacote foi instalado.

As regras principais são:

- CPU AMD planeja `amd-ucode`; CPU Intel planeja `intel-ucode`. Nunca ambos por padrão.
- Cada GPU detectada contribui com seus próprios componentes. Assim, máquinas híbridas podem receber componentes AMD e Intel, por exemplo.
- Bibliotecas gráficas 32-bit só entram no perfil `gaming`.
- NVIDIA não instala cegamente um módulo de kernel. O plano inclui o espaço de usuário disponível e avisa que a compatibilidade com kernel e repositórios deve ser confirmada.
- `NetworkManager` só é habilitado se ainda não estiver ativo.
- Bluetooth só entra se houver hardware detectado.
- `fstrim.timer` só entra se existir dispositivo não rotacional.
- Se já existe um display manager diferente do desktop selecionado, o novo não é habilitado silenciosamente. O plano mantém o atual e informa a situação.

Antes de executar, o plano mostra pacotes, serviços, itens deliberadamente não incluídos e as garantias de segurança. Sem `--yes`, a resposta padrão para a confirmação é não.

## 4. Execução

Após a confirmação, o executor trata primeiro os pacotes e depois os serviços.

Para cada pacote, ele verifica:

1. se já está instalado — registra como pré-existente;
2. se está disponível nos repositórios atualmente configurados — caso contrário, o ignora com aviso;
3. se precisa ser instalado — executa `sudo pacman -S --needed`.

Não há `--noconfirm`, atualização automática do sistema ou AUR obrigatório. A disponibilidade é consultada no próprio `pacman`, portanto a decisão se adapta aos repositórios configurados no computador naquele momento.

Para um serviço, o executor registra o estado anterior e só então executa `sudo systemctl enable`. Serviços já habilitados não são alterados.

## 5. Estado, logs e backups

O estado independente do diretório do projeto fica em:

```text
~/.local/state/arch-smart-postinstall/
├── state.json
├── installed-packages.txt
├── existing-packages.txt
├── modified-files.txt
├── services.txt
├── last-run
└── backups/
```

`installed-packages.txt` contém exclusivamente pacotes instalados pelo projeto. Isso é a proteção principal contra remover algo que o usuário já possuía. `existing-packages.txt` registra pacotes encontrados antes da execução. `services.txt` registra o serviço, seu estado anterior e o novo estado.

Em execuções reais, os logs são gravados como `logs/install-AAAA-MM-DD_HH-MM-SS.log` no diretório do projeto. Dry-run imprime a saída apenas no terminal. Com `--verbose`, mensagens de depuração também são emitidas.

Todo módulo que futuramente modificar arquivo deve chamar `backup_file arquivo módulo` antes da modificação. Ela cria uma cópia sob `backups/`, registra hash, data, módulo e caminho em um manifest. A implementação atual não altera arquivos de configuração por padrão, então não cria backups fictícios.

## 6. Validação e falhas

No fim, a validação confere se os pacotes planejados estão instalados e se os serviços planejados foram habilitados. Falhas são mostradas como `[WARN]`; o programa não declara sucesso sem evidência.

O shell usa `set -Eeuo pipefail` e um `trap` de erro. Uma falha crítica registra módulo, linha, comando e caminho do log. A execução não segue para os módulos posteriores como se nada tivesse acontecido.

## 7. Rollback e uninstall

```bash
./install.sh --rollback
./install.sh --uninstall
```

Os dois exibem o que farão e pedem confirmação. Rollback restaura arquivos com backup quando existirem, restaura o estado anterior dos serviços e tenta remover apenas os pacotes registrados como instalados pelo projeto. Uninstall limita-se a essa mesma lista de pacotes: não toca em arquivos pessoais, pacotes pré-existentes ou dados do usuário.

Antes de usar qualquer um deles, consulte o histórico:

```bash
./install.sh --list-changes
```

## Segurança deliberada

O projeto nunca chama comandos de particionamento, formatação ou limpeza de discos. Também não executa `curl | bash`, não adiciona repositórios externos, não instala AUR automaticamente, não modifica GRUB/systemd-boot, não aplica overclock/undervolt nem reinicia a máquina. Essas limitações são parte do funcionamento esperado, e não recursos ausentes por acidente.
